@Grapes([
	@Grab(group='com.rabbitmq', module='amqp-client', version='3.6.6'),
	@Grab(group='org.ehcache', module='ehcache', version='3.9.2'),
])
import groovy.json.JsonSlurper
import groovy.json.JsonOutput
import groovy.transform.SourceURI
import java.nio.charset.StandardCharsets
import java.nio.file.Path
import java.nio.file.Paths
import java.util.logging.Level
import java.util.logging.Logger
import com.rabbitmq.client.*
import org.ehcache.Cache
import org.ehcache.CacheManager
import static org.ehcache.config.builders.CacheConfigurationBuilder.newCacheConfigurationBuilder
import static org.ehcache.config.builders.CacheManagerBuilder.newCacheManagerBuilder
import static org.ehcache.config.builders.ResourcePoolsBuilder.heap

def createRabbitMQConnection() {
    def factory = new ConnectionFactory()
    return factory.newConnection()
}

class ChannelFolder {
		String kind = "folder"
		String id
		String name
}

class TimelineItemFolder {
		String kind = "folder"
		String id
		String name

		TimelineItemFolder(item) {
				this.id = item.id
				this.name = item.id.startsWith("#") ? item.id.substring(1) : item.id
		}
}

class TimelineItemPropertyFile {
		String kind = "file"
		String id
		String name
		String content = null

		TimelineItemPropertyFile(timelineItem, propertyName, withContent) {
				String fileId = "${timelineItem.id}#${propertyName}"
				this.id = fileId
				this.name = propertyName
				if (withContent) {
						def values = timelineItem.getProperty(propertyName)
						if (values.size() > 0) {
								this.content = values[0].getDefaultValue().getBytes('UTF8').encodeBase64().toString()
						} else {
								this.content = ""
						}
				}
		}
}

def getChannel(cache, plrutil, channelId) {
		def cached = cache.get(channelId)
		if (cached != null) {
				return cached
		}
		def obj = plrutil.listAllChannels().find { it.getId() == channelId }
		if (obj == null) {
				throw new IllegalArgumentException("Not found: ${channelId}")
		}
		cache.put(obj.getId(), obj)
		return obj
}

def getTimelineItem(cache, plrutil, channelId, itemId) {
		String cacheId = "${channelId}/${itemId}"
		def cached = cache.get(cacheId)
		if (cached != null) {
				return cached
		}
		def channel = getChannel(cache, plrutil, channelId)
		def items = channel.getTimelineItems(
				new Date((long)(System.currentTimeMillis() - 1000L * 60 * 60 * 24 * 365 * 5)),
				new Date()
		)
		items.each {
				String itemCacheId = "${channelId}/${it.id}"
				cache.put(itemCacheId, it)
		}
		def obj = items.find { it.id == itemId }
		if (obj == null) {
				throw new IllegalArgumentException("Not found: ${itemId} on ${channelId}")
		}
		return obj
}

def performGetFiles(logger, cache, plrutil, path) {
		if (path.size() == 0) {
				// root folder
				def channels = plrutil.listAllChannels()
				channels.each {
						cache.put(it.getId(), it)
				}
				return channels.collect {
					new ChannelFolder( id: it.getId(), name: it.getName() )
				}
		} else if (path.size() == 1) {
				// timeline item
				def channel = getChannel(cache, plrutil, path[0])
				def items = channel.getTimelineItems(
						new Date((long)(System.currentTimeMillis() - 1000L * 60 * 60 * 24 * 365 * 5)),
						new Date()
				)
				logger.info "getTimelineItems items=${items.size()}"
				items.each {
						String cacheId = "${path[0]}/${it.id}"
						cache.put(cacheId, it)
				}
				return items.collect { new TimelineItemFolder(it) }
		} else if (path.size() == 2) {
				// timeline property
				def item = getTimelineItem(cache, plrutil, path[0], path[1])
				return item.propertyNames().collect { new TimelineItemPropertyFile(item, it, false) }
		}
		throw new UnsupportedOperationException("Unexpected path: ${path}")
}

def performGetFile(logger, cache, plrutil, path) {
		if (path.size() == 3) {
				// timeline property
				def item = getTimelineItem(cache, plrutil, path[0], path[1])
				if (!path[2].startsWith("${path[1]}#")) {
						throw new IllegalArgumentException("Not found: ${path[2]} on ${path[0]}/${path[1]}")
				}
				def propertyName = path[2].substring(path[1].length() + 1)
				if (!item.propertyNames().contains(propertyName)) {
						logger.info "Property names: ${item.propertyNames()} - ${propertyName}"
						throw new IllegalArgumentException("Not found: ${path[2]} on ${path[0]}/${path[1]}")
				}
				return new TimelineItemPropertyFile(item, propertyName, true)
		}
		throw new UnsupportedOperationException("Unexpected path: ${path}")
}

class SerializableError {
		String className
		String message

		SerializableError(Throwable e) {
				this.className = e.getClass().getName()
				this.message = e.getMessage()
		}
}

class RPCResult {
	  boolean success = true
		def error = null
		def result = null
}

def performRPC(logger, cacheManager, plrutil, event) {
		logger.info "Event: ${event.name}"
		def cache = cacheManager.getCache("PLRobjects", String.class, Object.class)
		if (event.name == 'get-files') {
				try {
						return new RPCResult( result: performGetFiles(logger, cache, plrutil, event.path) )
				} catch(Exception e) {
						logger.log(Level.WARNING, "Failed to perform ${event.name}", e)
						return new RPCResult( success: false, error: new SerializableError(e) )
				}
		} else if (event.name == 'get-file'){
				try {
						return new RPCResult( result: performGetFile(logger, cache, plrutil, event.path) )
				} catch(Exception e) {
						logger.log(Level.WARNING, "Failed to perform ${event.name}", e)
						return new RPCResult( success: false, error: new SerializableError(e) )
				}
		}
		def e = new IllegalArgumentException("Unexpected function name: ${event.name}")
		return new RPCResult( success: false, error: new SerializableError(e) )
}

@SourceURI
URI sourceUri

Path scriptLocation = Paths.get(sourceUri)
def logger = Logger.getLogger(scriptLocation.toString())

def plrutil = evaluate(scriptLocation.getParent().resolve("plrutil.groovy").toFile())

logger.info "Initializing connection to services..."

def conn = createRabbitMQConnection()
def channel = conn.createChannel()
boolean durable = false
channel.queueDeclare("plrfsrpc", durable, false, false, null)

boolean noAck = false
def consumer = new QueueingConsumer(channel)
channel.basicConsume("plrfsrpc", noAck, consumer)

plrutil.init()

def jsonSlurper = new JsonSlurper()

def plrId = plrutil.getMyPlrId()
logger.info "PLR started: ${plrId}"
def running = true

CacheManager cacheManager = newCacheManagerBuilder()
    .withCache("PLRobjects", newCacheConfigurationBuilder(String.class, Object.class, heap(1024L * 100)))
    .build(true)

while(running) {
  QueueingConsumer.Delivery delivery
  try {
      delivery = consumer.nextDelivery();
			def callerProps = delivery.getProperties()
      def event = jsonSlurper.parseText(new String(delivery.body, StandardCharsets.UTF_8))
      def result = performRPC(logger, cacheManager, plrutil, event)
			def resultBytes = JsonOutput.toJson(result).getBytes('UTF8')
			BasicProperties props = new AMQP.BasicProperties.Builder()
			                            .correlationId(callerProps.getCorrelationId())
			                            .build()
			channel.basicPublish("", callerProps.getReplyTo(), props, resultBytes);
  } catch (InterruptedException ie) {
      logger.info ie.getMessage()
      running = false
  }
  channel.basicAck(delivery.getEnvelope().getDeliveryTag(), false);
}

logger.info "Exiting... "
plrutil.destroy()
logger.info "done."
