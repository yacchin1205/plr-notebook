import java.util.logging.Logger
import java.text.SimpleDateFormat
import com.assemblogue.plr.lib.PLR
import com.assemblogue.plr.io.Storage
import com.assemblogue.plr.lib.PLR.StorageNeedPassphraseException
import com.assemblogue.plr.lib.LiteralNode
import com.assemblogue.plr.lib.model.FriendUtils
import com.assemblogue.plr.io.PlrEntry.Origin
import com.assemblogue.plr.io.PlrEntry
import com.assemblogue.plr.lib.EntityNode
import com.assemblogue.plr.lib.EntityNode.TimelineItemsCallback

class TimelineItemsHandler implements TimelineItemsCallback {

    Logger logger = Logger.getLogger(TimelineItemsHandler.class.getName())

    def finished = false

    def allItems = []

    synchronized def waitFinish() {
        while (!finished) {
            synchronized(this) {
                wait()
            }
        }
        return allItems
    }

    void onError(EntityNode node, PlrEntry entry, Exception exception,
												Origin origin) {
			  // result.addException(entry, exception, origin);
        logger.error "onError: ${exception.getClass().getName()}: ${exception.getMessage()}"
		}

		synchronized void onFinish(EntityNode node) {
        logger.info "onFinished"
        finished = true
        notifyAll()
		}

    synchronized void onUpdate(EntityNode node, Collection items) {
        logger.info "onUpdate: items=${items.size()}"
        allItems = new ArrayList(items)
        notifyAll()
    }

}

class BaseChannel {
    Logger logger = Logger.getLogger(BaseChannel.class.getName())

    def getTimelineItems(node, beginDate, endDate) {
        logger.info "Starting... ${beginDate} - ${endDate}"
        def handler = new TimelineItemsHandler()
        node.getTimelineItems(beginDate, endDate, handler)
        def items = handler.waitFinish()
        items.sort {left, right -> left.getProperty("begin")[0].getDefaultValue() <=> right.getProperty("begin")[0].getDefaultValue()}
        logger.info "Completed: items=${items.size()}"
        return items
    }
}

class MyChannel extends BaseChannel {
    def channel = null

    def MyChannel(channel) {
        this.channel = channel
    }

    def getId() {
        return this.channel.id
    }

    def getName() {
        this.channel.syncAndWait()
        return this.channel.getDefaultName()
    }

    def getTimelineItems(beginDate, endDate) {
        this.channel.syncAndWait()
        return super.getTimelineItems(channel.getNode(), beginDate, endDate)
    }
}

class FriendToMeChannel extends BaseChannel {
    def channel = null

    def FriendToMeChannel(channel) {
        this.channel = channel
    }

    def getId() {
        return this.channel.id
    }

    def getName() {
        this.channel.syncAndWait()
        return this.channel.getDefaultName()
    }

    def getTimelineItems(beginDate, endDate) {
        return super.getTimelineItems(channel.getNode(), beginDate, endDate)
    }
}

class PLRUtil {
    PLR plr = null

    Storage storage = null

    Logger logger = Logger.getLogger(PLRUtil.class.getName())

    def init() {
        logger.info "Preparing PLR... "
        this.plr = PLR.createBuilder().build()
        logger.info "done."

        def storageId = System.getenv("STORAGE_ID")
        if (storageId == null || storageId == "") {
            throw new IllegalArgumentException("STORAGE_ID environment not set")
        }
        def passphrase = System.getenv("PASSPHRASE")
        if (passphrase == null || passphrase == "") {
            throw new IllegalArgumentException("PASSPHRASE environment not set")
        }

        def storageInfo = connectStorage(storageId)
        try {
            this.storage = plr.connectStorage(storageInfo)
        } catch (StorageNeedPassphraseException e) {
          	this.storage = e.postPassphrase(passphrase);
        }
        setupKeyPair(passphrase);
    }

    def destroy() {
        logger.info "Exiting... "
        plr.destroy()
        logger.info "done."
    }

    def connectStorage(storageId) {
        for (storage in Storage.list()) {
            if (Long.parseLong(storageId) == storage.getId()) {
                return storage;
            }
        }
        throw new IllegalArgumentException("Storage not found: $storageId")
    }

    def setupKeyPair(passphrase) {
        if (storage.hasKeyPair()) {
            return;
        }
    		logger.info "private key was not decoded."
    		logger.info "Decoding private key... "
    		if (storage.postPassphrase(passphrase)) {
    			logger.info "done."
    			return;
    		}
    		throw new IllegalArgumentException("invalid passphrase.");
    }

    def createFriendRequest() {
        def friendRequest = plr.createFriendRequest(storage)
        return [
            rawFriendRequest: friendRequest,
            plrctlWrappedURI: FriendUtils.wrapRequest(friendRequest, false).toString(),
            httpWrappedURI: FriendUtils.wrapRequest(friendRequest, true).toString()
        ]
    }

    def listAllChannels() {
        def root = plr.getRoot(storage)
        root.syncAndWait()
        def channels = []
        for (def channel in root.listChannels()) {
            channels.add(new MyChannel(channel))
        }
        for (def friend in root.listFriends()) {
            def f2meRoot = friend.getFriendToMeRoot()
            f2meRoot.syncAndWait()
            for (def channel in f2meRoot.listReferencingChannels()) {
                channels.add(new FriendToMeChannel(channel))
            }
        }
        return channels
    }

    def listFriendsWithSharedChannel(channelName) {
        def root = plr.getRoot(storage)
        root.syncAndWait()
        def friends = [:]
        logger.info "Searching $channelName ..."
        for (def friend in root.listFriends()) {
            def channel = getSharedChannel(friend, channelName)
            if (channel == null) {
                continue
            }
            friends[friend.getPlrId()] = channel.getId()
        }
        return friends
    }

    def getMyPlrId() {
        return "${storage.getType().getName()}:${storage.getUserId()}"
    }

    def getSharedChannel(friend, channelName) {
        def f2meRoot = friend.getFriendToMeRoot()
        f2meRoot.syncAndWait()
        for (def channel in f2meRoot.listReferencingChannels()) {
            channel.syncAndWait()
            logger.info "${friend.getPlrId()} - ${channel.getDefaultName()}"
            if (channel.getDefaultName() == channelName) {
                return channel
            }
        }
        return null
    }

    def addFriend(friendRequest) {
        def root = plr.getRoot(storage)
        root.syncAndWait()
        root.addFriend(friendRequest)
        root.syncAndWait()
    }

    def addItem(toPlrId, channelName, createdTime, payload) {
        def root = plr.getRoot(storage);
        root.syncAndWait()
        def friend = root.getFriend(toPlrId);
        if (friend == null) {
            logger.warning "No friend: $toPlrId"
            return
        }
        def channel = getSharedChannel(friend, channelName)
        if (channel == null) {
            logger.warning "No channel: $toPlrId - $channelName"
            return
        }
        def node = channel.getNode()
        def dateFormat = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX");
        def item = node.newTimelineItem("M", dateFormat.format(createdTime), true)
        def creatorNode = item.newLiteral("creator")
        creatorNode.setValue(LiteralNode.LANG_NONE, getMyPlrId())
        payload.each { entry ->
            def contentNode = item.newLiteral(entry.key)
            contentNode.setValue(LiteralNode.LANG_NONE, entry.value)
        }
        item.syncAndWait(true)
        channel.syncAndWait()
        def f2meRoot = friend.getFriendToMeRoot()
        f2meRoot.syncAndWait()
        root.syncAndWait()
    }

    def sync() {
        logger.info "Perform sync command..."
        def sout = new StringBuilder(), serr = new StringBuilder()
        def proc = 'plr-sync'.execute()
        proc.consumeProcessOutput(sout, serr)
        proc.waitForOrKill(30000)
        logger.info "out> $sout\nerr> $serr"
    }
}

return new PLRUtil()
