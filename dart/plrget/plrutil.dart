import 'dart:async';
import 'dart:io';
import 'package:_plr_common/_plr_common.dart';
import 'package:plr_command/src/commands/storage_command.dart';
import 'package:plr_command/src/shell.dart';

import 'logger.dart';

dynamic getValueOf(Iterable<Node> nodes) {
  if (nodes.isEmpty) {
    return null;
  }
  final node = nodes.first;
  if (node is LiteralNode) {
    return node.defaultValue;
  } else {
    logger.w('Unsupported node type: ${node.runtimeType}');
    return node.toString();
  }
}

class SimpleItem {
  final EntityNode raw;

  SimpleItem(this.raw);

  get id => raw.id;

  Map<String, dynamic> toJson() {
    final r = <String, dynamic>{'id': id};
    for (final property in raw.propertyEntries) {
      logger.d('Property: ${property.key} - ${property.value}');
      r[property.key] = getValueOf(property.value);
    }
    return r;
  }
}

class SimpleChannel {
  final String id;
  final String name;
  final Channel raw;

  SimpleChannel(this.id, this.name, this.raw);

  get absoluteName => name;

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'absoluteName': absoluteName};
  }

  Future<Iterable<SimpleItem>> getTimelineItems(
      DateTime begin, DateTime end) async {
    logger.i('Getting timeline items: $begin - $end');
    await raw.syncSilently();
    final items = raw.timelineItems(begin, end);
    final results = <SimpleItem>[];
    final resultIds = <String>{};
    await for (final items in items.handleError((e) {
      logger.e(e);
      throw e;
    })) {
      for (final item in items) {
        await item.syncSilently();
        logger.d('Item: ${item}');
        if (resultIds.contains(item.id)) {
          continue;
        }
        results.add(SimpleItem(item));
        resultIds.add(item.id ?? '');
      }
    }
    return results;
  }
}

class FriendToMeChannel extends SimpleChannel {
  final String friendPlrId;

  FriendToMeChannel(String id, String name, this.friendPlrId, Channel raw)
      : super(id, name, raw);

  @override
  get absoluteName => '$name(from $friendPlrId)';

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'absoluteName': absoluteName,
      'friendPlrId': friendPlrId
    };
  }
}

class PLRUtil {
  Storage? storage;

  Future<void> init() async {
    logger.i('Preparing PLR...');
    final env = Platform.environment;
    final storageId = env['STORAGE_ID'];
    if (storageId == null || storageId.isEmpty) {
      throw ArgumentError('STORAGE_ID environment not set');
    }
    final passphrase = env['PASSPHRASE'];
    if (passphrase == null || passphrase.isEmpty) {
      throw ArgumentError('PASSPHRASE environment not set');
    }

    final storage = await _connectStorage(storageId, passphrase);
    logger.i('Connected to storage: ${storage.id}');
    this.storage = storage;
  }

  Future<void> destroy() async {
    logger.i('Exiting...');
    if (storage != null) {
      storage!.close();
    }
    logger.i('done.');
  }

  Future<Storage> _connectStorage(String storageId, String passphrase) async {
    final storage = await connect(storageId, passphrase);
    if (storage == null) {
      throw ArgumentError('failed to connect to storage #$storageId');
    }
    return storage;
  }

  Future<SimpleChannel> getChannel(String channelId) async {
    final root = await rootOf(storage!);
    await root.syncSilently();

    logger.i('Searching $channelId ...');
    for (final channel in root.channels) {
      await channel.syncSilently();
      logger.i('Channel: ${channel.id} - ${_defaultValueOrNone(channel.name)}');
      if (channel.id.toString() == channelId) {
        return SimpleChannel(
            channel.id.toString(), _defaultValueOrNone(channel.name), channel);
      }
    }
    await for (final r in root.friends.handleError((e) {
      logger.e(e);
      throw e;
    })) {
      logger.d('Friends from ${originNameOf(r.origin)}');
      final friends = await r.value.toList();
      final friendsWithSharedChannels =
          await Future.wait(friends.map((friend) async {
        logger.d('Friend: ${friend.plrId}');
        await friend.syncSilently();
        final channel = await findSharedChannelById(friend, channelId);
        if (channel == null) {
          return null;
        }
        logger.i(
            'Shared channel: ${friend.plrId} - ${_defaultValueOrNone(channel.name)}');
        return FriendToMeChannel(
            channel.id.toString(),
            _defaultValueOrNone(channel.name),
            friend.plrId.toString(),
            channel);
      }));
      for (final friendChannel in friendsWithSharedChannels) {
        if (friendChannel != null) {
          return friendChannel;
        }
      }
    }
    throw ArgumentError('Channel not found: $channelId');
  }

  Future<List<SimpleChannel>> listAllChannels() async {
    final root = await rootOf(storage!);
    await root.syncSilently();

    logger.i('Searching all channels ...');
    final channels = <SimpleChannel>[];
    for (final channel in root.channels) {
      await channel.syncSilently();
      logger.i('Channel: ${channel.id} - ${_defaultValueOrNone(channel.name)}');
      channels.add(SimpleChannel(
          channel.id.toString(), _defaultValueOrNone(channel.name), channel));
    }
    await for (final r in root.friends.handleError((e) {
      logger.e(e);
      throw e;
    })) {
      logger.d('Friends from ${originNameOf(r.origin)}');
      final friends = await r.value.toList();
      final friendsWithSharedChannel =
          await Future.wait(friends.map((friend) async {
        logger.d('Friend: ${friend.plrId}');
        await friend.syncSilently();
        final friendChannels = await getSharedChannels(friend);
        if (friendChannels == null) {
          logger.w('Shared channels are null for ${friend.plrId}');
          return null;
        }
        logger.i('Shared channels: ${friend.plrId}');
        return friendChannels.map((channel) {
          return FriendToMeChannel(
              channel.id.toString(),
              _defaultValueOrNone(channel.name),
              friend.plrId.toString(),
              channel);
        });
      }));
      for (final friendChannels in friendsWithSharedChannel) {
        if (friendChannels != null) {
          channels.addAll(friendChannels);
        }
      }
    }
    logger.i('Found ${channels.length} channels.');
    return channels;
  }

  Future<Map<String, String>> listFriendsWithSharedChannel(
      String channelName) async {
    final root = await rootOf(storage!);
    await root.syncSilently();

    final result = <String, String>{};
    logger.i('Searching $channelName ...');
    await for (final r in root.friends.handleError((e) {
      logger.e(e);
      throw e;
    })) {
      logger.d('Friends from ${originNameOf(r.origin)}');
      final friends = await r.value.toList();
      final friendsWithSharedChannel =
          await Future.wait(friends.map((friend) async {
        logger.d('Friend: ${friend.plrId}');
        await friend.syncSilently();
        final channel = await getSharedChannel(friend, channelName);
        if (channel == null) {
          logger.w('Shared channel is null for ${friend.plrId}');
          return null;
        }
        logger.i(
            'Shared channel: ${friend.plrId} - ${_defaultValueOrNone(channel.name)}');
        return {
          'friendPlrId': friend.plrId.toString(),
          'channelId': channel.id.toString(),
        };
      }));
      for (final friend in friendsWithSharedChannel) {
        if (friend != null) {
          result[friend['friendPlrId']!] = friend['channelId']!;
        }
      }
    }
    logger.i('Found ${result.length} friends with shared channel.');
    return result;
  }

  String _defaultValueOrNone(Literal? literal) =>
      literal?.defaultValue ?? "none";

  Future<Channel?> getSharedChannel(Friend friend, String channelName) async {
    final f2meRoot = friend.friendToMeRoot;
    if (f2meRoot == null) {
      logger.w('FriendToMeRoot is null for ${friend.plrId}');
      return null;
    }
    logger.i('Syncing ${friend.plrId} ...');
    await f2meRoot.syncSilently();
    logger.i('Done.');
    for (final channel in f2meRoot.channels) {
      await channel.syncSilently();
      logger.d('${friend.plrId} - ${_defaultValueOrNone(channel.name)}');
      if (_defaultValueOrNone(channel.name) == channelName) {
        return channel;
      }
    }
    return null;
  }

  Future<Channel?> findSharedChannelById(
      Friend friend, String channelId) async {
    final f2meRoot = friend.friendToMeRoot;
    if (f2meRoot == null) {
      logger.w('FriendToMeRoot is null for ${friend.plrId}');
      return null;
    }
    logger.i('Syncing ${friend.plrId} ...');
    await f2meRoot.syncSilently();
    logger.i('Done.');
    for (final channel in f2meRoot.channels) {
      await channel.syncSilently();
      logger.d('${friend.plrId} - ${_defaultValueOrNone(channel.name)}');
      if (channel.id.toString() == channelId) {
        return channel;
      }
    }
    return null;
  }

  Future<List<Channel>?> getSharedChannels(Friend friend) async {
    final f2meRoot = friend.friendToMeRoot;
    if (f2meRoot == null) {
      logger.w('FriendToMeRoot is null for ${friend.plrId}');
      return null;
    }
    logger.i('Syncing ${friend.plrId} ...');
    await f2meRoot.syncSilently();
    logger.i('Done.');
    final channels = <Channel>[];
    for (final channel in f2meRoot.channels) {
      await channel.syncSilently();
      logger.d('${friend.plrId} - ${_defaultValueOrNone(channel.name)}');
      channels.add(channel);
    }
    return channels;
  }

  PlrId getMyPlrId() {
    return storage!.plrId;
  }
}
