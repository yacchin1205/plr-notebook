@Grapes([
	@Grab(group='org.ehcache', module='ehcache', version='3.9.2'),
	@Grab(group='org.zeromq', module='jeromq', version='0.5.2'),
])
import groovy.json.JsonSlurper
import groovy.json.JsonOutput
import groovy.transform.SourceURI
import java.nio.charset.StandardCharsets
import java.nio.file.Path
import java.nio.file.Paths
import java.util.logging.Level
import java.util.logging.Logger
import org.ehcache.Cache
import org.ehcache.CacheManager
import static org.ehcache.config.builders.CacheConfigurationBuilder.newCacheConfigurationBuilder
import static org.ehcache.config.builders.CacheManagerBuilder.newCacheManagerBuilder
import static org.ehcache.config.builders.ResourcePoolsBuilder.heap
import org.zeromq.ZMQ
import org.zeromq.ZContext

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

plrutil.init()

def jsonSlurper = new JsonSlurper()

def plrId = plrutil.getMyPlrId()
logger.info "PLR started: ${plrId}"
def running = true

def cacheHeapSizeText = System.getenv("PLR_CACHE_HEAP_SIZE");
def cacheHeapSize = 1024L * 1024; // Default: 1MB
if (cacheHeapSizeText != null && cacheHeapSizeText != "") {
	cacheHeapSize = Long.valueOf(cacheHeapSizeText);
}

CacheManager cacheManager = newCacheManagerBuilder()
    .withCache("PLRobjects", newCacheConfigurationBuilder(String.class, Object.class, heap(cacheHeapSize)))
    .build(true)

def portNumber = System.getenv("PLR_ZEROMQ_PORT") ?: "5555"

try (def zcontext = new ZContext()) {
	// Socket to talk to clients
	def socket = zcontext.createSocket(ZMQ.REP);
	socket.bind("tcp://*:" + portNumber);

	while (!Thread.currentThread().isInterrupted()) {
		def message = socket.recv(0);
	    def event = jsonSlurper.parseText(new String(message, StandardCharsets.UTF_8))
	    def result = performRPC(logger, cacheManager, plrutil, event)
		def resultBytes = JsonOutput.toJson(result).getBytes(StandardCharsets.UTF_8)
		socket.send(resultBytes, 0);
	}
}

logger.info "Exiting... "
plrutil.destroy()
logger.info "done."
