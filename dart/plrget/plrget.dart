import 'dart:convert';
import 'dart:io';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

import 'package:plr_console/plr_console.dart';

import 'plrutil.dart';
import 'logger.dart';

final DEFAULT_TIMELINE_SINCE_DAYS = 7;

// TODO: Replace placeholder imports with actual Dart library or implementation
// import 'package:org.ehcache.dart';
// import 'package:org.zeromq.dart';

/*
class ChannelFolder {
  String kind = "folder";
  String id;
  String name;

  ChannelFolder({required this.id, required this.name});
}

class TimelineItemFolder {
  String kind = "folder";
  String id;
  String name;

  TimelineItemFolder(dynamic item)
      : id = item.id,
        name = item.id.startsWith("#") ? item.id.substring(1) : item.id;
}

class TimelineItemPropertyFile {
  String kind = "file";
  String id;
  String name;
  String? content;

  TimelineItemPropertyFile(dynamic timelineItem, String propertyName, bool withContent) {
    id = "${timelineItem.id}#$propertyName";
    name = propertyName;
    if (withContent) {
      var values = timelineItem.getProperty(propertyName);
      content = values.isNotEmpty ? base64.encode(utf8.encode(values[0].getDefaultValue())) : "";
    }
  }
}

dynamic getChannel(dynamic cache, dynamic plrutil, String channelId) {
  var cached = cache[channelId];
  if (cached != null) {
    return cached;
  }
  var obj = plrutil.listAllChannels().firstWhere((ch) => ch.getId() == channelId, orElse: () => null);
  if (obj == null) {
    throw ArgumentError("Not found: $channelId");
  }
  cache[channelId] = obj;
  return obj;
}

dynamic getTimelineItem(dynamic cache, dynamic plrutil, String channelId, String itemId) {
  var cacheId = "$channelId/$itemId";
  var cached = cache[cacheId];
  if (cached != null) {
    return cached;
  }
  var channel = getChannel(cache, plrutil, channelId);
  var items = channel.getTimelineItems(
    DateTime.now().subtract(Duration(days: 365 * 5)),
    DateTime.now(),
  );
  for (var it in items) {
    cache["$channelId/${it.id}"] = it;
  }
  var obj = items.firstWhere((it) => it.id == itemId, orElse: () => null);
  if (obj == null) {
    throw ArgumentError("Not found: $itemId on $channelId");
  }
  return obj;
}

List<dynamic> performGetFiles(Logger logger, dynamic cache, dynamic plrutil, List<String> path) {
  if (path.isEmpty) {
    var channels = plrutil.listAllChannels();
    for (var ch in channels) {
      cache[ch.getId()] = ch;
    }
    return channels.map((ch) => ChannelFolder(id: ch.getId(), name: ch.getName())).toList();
  } else if (path.length == 1) {
    var channel = getChannel(cache, plrutil, path[0]);
    var items = channel.getTimelineItems(
      DateTime.now().subtract(Duration(days: 365 * 5)),
      DateTime.now(),
    );
    logger.i("getTimelineItems items=${items.length}");
    for (var it in items) {
      cache["${path[0]}/${it.id}"] = it;
    }
    return items.map((it) => TimelineItemFolder(it)).toList();
  } else if (path.length == 2) {
    var item = getTimelineItem(cache, plrutil, path[0], path[1]);
    return item.propertyNames().map((prop) => TimelineItemPropertyFile(item, prop, false)).toList();
  }
  throw UnsupportedError("Unexpected path: $path");
}

TimelineItemPropertyFile performGetFile(Logger logger, dynamic cache, dynamic plrutil, List<String> path) {
  if (path.length == 3) {
    var item = getTimelineItem(cache, plrutil, path[0], path[1]);
    if (!path[2].startsWith("${path[1]}#")) {
      throw ArgumentError("Not found: ${path[2]} on ${path[0]}/${path[1]}");
    }
    var propertyName = path[2].substring(path[1].length + 1);
    if (!item.propertyNames().contains(propertyName)) {
      logger.i("Property names: ${item.propertyNames()} - $propertyName");
      throw ArgumentError("Not found: ${path[2]} on ${path[0]}/${path[1]}");
    }
    return TimelineItemPropertyFile(item, propertyName, true);
  }
  throw UnsupportedError("Unexpected path: $path");
}

class SerializableError {
  String className;
  String message;

  SerializableError(Exception e)
      : className = e.runtimeType.toString(),
        message = e.toString();
}

class RPCResult {
  bool success;
  dynamic error;
  dynamic result;

  RPCResult({this.success = true, this.error, this.result});
}

RPCResult performRPC(Logger logger, dynamic cacheManager, dynamic plrutil, Map<String, dynamic> event) {
  logger.i("Event: ${event['name']}");
  var cache = cacheManager["PLRobjects"];
  if (event['name'] == 'get-files') {
    try {
      return RPCResult(result: performGetFiles(logger, cache, plrutil, event['path']));
    } catch (e) {
      logger.w("Failed to perform ${event['name']}", e);
      return RPCResult(success: false, error: SerializableError(e as Exception));
    }
  } else if (event['name'] == 'get-file') {
    try {
      return RPCResult(result: performGetFile(logger, cache, plrutil, event['path']));
    } catch (e) {
      logger.w("Failed to perform ${event['name']}", e);
      return RPCResult(success: false, error: SerializableError(e as Exception));
    }
  }
  var e = ArgumentError("Unexpected function name: ${event['name']}");
  return RPCResult(success: false, error: SerializableError(e));
}
*/

class BaseOutput {
  final encode = (message) => JsonEncoder().convert(message);

  void write(Map<String, dynamic> message) {
    throw UnimplementedError();
  }

  void close() {
    // Do nothing
  }
}

class StdoutOutput extends BaseOutput {
  @override
  void write(Map<String, dynamic> message) {
    print(encode(message));
  }
}

class FileOutput extends BaseOutput {
  IOSink? file = null;

  FileOutput(String path) {
    file = io.File(path).openWrite();
  }

  @override
  void write(Map<String, dynamic> message) {
    if (file == null) {
      throw StateError("File not opened");
    }
    file!.write("${encode(message)}\n");
  }

  @override
  void close() {
    if (file == null) {
      return;
    }
    file!.close();
    file = null;
  }
}

void main(List<String> arguments) async {
  final parser = ArgParser();
  parser.addFlag("verbose", abbr: "v", defaultsTo: false);
  parser.addOption("output", abbr: "o", defaultsTo: "stdout");
  // List channels: plrget ls
  // List timeline items: plrget ls --since=YYYY-MM-DDTHH:mm:ss --untile=YYYY-MM-DDTHH:mm:ss channelId
  final listParser = parser.addCommand("list");
  listParser.addOption("since");
  listParser.addOption("until");

  final args = parser.parse(arguments);
  final command = args.command;
  if (command == null) {
    print(arguments);
    print(parser.usage);
    throw ArgumentError("No command specified");
  }

  if (args["verbose"]) {
    logFilter.verbose = true;
  }

  final plrutil = PLRUtil();
  final env = Platform.environment;
  final plrDirectory = env["PLR_DIRECTORY"];
  if (plrDirectory == null || plrDirectory.isEmpty) {
    throw ArgumentError("PLR_DIRECTORY environment not set");
  }

  await initPlr({
    plrDirectoryParam: plrDirectory,
  });

  await plrutil.init();

  logger.i("PLR started: ${plrutil.getMyPlrId()}");

  final output =
      args["output"] == "stdout" ? StdoutOutput() : FileOutput(args["output"]);
  try {
    if (command.name == "list") {
      if (command.rest.isEmpty) {
        if (command["since"] != null) {
          throw ArgumentError("Since is not allowed without channelId");
        }
        if (command["until"] != null) {
          throw ArgumentError("Until is not allowed without channelId");
        }
        final channels = await plrutil.listAllChannels();
        for (final ch in channels) {
          output.write(ch.toJson());
        }
      } else {
        final channelId = command.rest[0];
        final channel = await plrutil.getChannel(channelId);
        final since = command["since"] != null
            ? DateTime.parse(command["since"]!)
            : DateTime.now()
                .subtract(Duration(days: DEFAULT_TIMELINE_SINCE_DAYS));
        final until = command["until"] != null
            ? DateTime.parse(command["until"]!)
            : DateTime.now();
        final items = await channel.getTimelineItems(since, until);
        for (final it in items) {
          output.write(it.toJson());
        }
      }
    }
  } finally {
    output.close();
  }

  /*
  // Cache setup
  var cacheManager = {}; // Replace with actual cache manager implementation

  var server = RawDatagramSocket.bind(InternetAddress.anyIPv4, 5555);
  server.then((socket) {
    logger.i("Server listening on port 5555");
    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        var message = socket.receive();
        if (message != null) {
          var event = jsonDecode(utf8.decode(message.data));
          var result = performRPC(logger, cacheManager, plrutil, event);
          socket.send(utf8.encode(jsonEncode(result)), message.address, message.port);
        }
      }
    });
  });
  */
}
