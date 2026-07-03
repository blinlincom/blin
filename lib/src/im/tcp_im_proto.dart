import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

enum TcpPacketType {
  reserved,
  connect,
  connack,
  send,
  sendack,
  recv,
  recvack,
  ping,
  pong,
  disconnect,
}

class TcpPacketHeader {
  TcpPacketType packetType = TcpPacketType.reserved;
  bool showUnread = false;
  bool noPersist = false;
  bool syncOnce = false;
  bool hasServerVersion = false;
  int remainingLength = 0;
}

abstract class TcpPacket {
  TcpPacket(this.packetType);

  final TcpPacketType packetType;
  TcpPacketHeader header = TcpPacketHeader();
}

class TcpConnectPacket extends TcpPacket {
  TcpConnectPacket({
    required this.version,
    required this.deviceFlag,
    required this.deviceId,
    required this.uid,
    required this.token,
    required this.clientTimestamp,
    required this.clientKey,
  }) : super(TcpPacketType.connect);

  final int version;
  final int deviceFlag;
  final String deviceId;
  final String uid;
  final String token;
  final int clientTimestamp;
  final String clientKey;
}

class TcpConnackPacket extends TcpPacket {
  TcpConnackPacket() : super(TcpPacketType.connack);

  int serviceProtoVersion = 4;
  int timeDiff = 0;
  int reasonCode = 0;
  String serverKey = '';
  String salt = '';
  int nodeId = 0;
}

class TcpSendAckPacket extends TcpPacket {
  TcpSendAckPacket() : super(TcpPacketType.sendack);

  String messageId = '';
  int clientSeq = 0;
  int messageSeq = 0;
  int reasonCode = 0;
}

class TcpRecvPacket extends TcpPacket {
  TcpRecvPacket() : super(TcpPacketType.recv);

  TcpSetting setting = TcpSetting();
  String msgKey = '';
  String fromUid = '';
  String channelId = '';
  int channelType = 0;
  int expire = 0;
  String clientMsgNo = '';
  String streamNo = '';
  int streamSeq = 0;
  int streamFlag = 0;
  BigInt messageId = BigInt.zero;
  int messageSeq = 0;
  int messageTime = 0;
  String topic = '';
  String payload = '';
}

class TcpRecvAckPacket extends TcpPacket {
  TcpRecvAckPacket({required this.messageId, required this.messageSeq})
    : super(TcpPacketType.recvack);

  final BigInt messageId;
  final int messageSeq;
}

class TcpDisconnectPacket extends TcpPacket {
  TcpDisconnectPacket() : super(TcpPacketType.disconnect);

  int reasonCode = 0;
  String reason = '';
}

class TcpPingPacket extends TcpPacket {
  TcpPingPacket() : super(TcpPacketType.ping);
}

class TcpPongPacket extends TcpPacket {
  TcpPongPacket() : super(TcpPacketType.pong);
}

class TcpSetting {
  int receipt = 0;
  int topic = 0;
  int stream = 0;

  TcpSetting decode(int value) {
    receipt = value >> 7 & 0x01;
    topic = value >> 3 & 0x01;
    stream = value >> 2 & 0x01;
    return this;
  }

  int encode() {
    return receipt << 7 | topic << 3 | stream << 2;
  }
}

class TcpImProto {
  TcpImProto({this.protoVersion = 4});

  final int protoVersion;
  int negotiatedProtoVersion = 4;

  Uint8List encode(TcpPacket packet) {
    final body = switch (packet.packetType) {
      TcpPacketType.connect => _encodeConnect(packet as TcpConnectPacket),
      TcpPacketType.recvack => _encodeRecvAck(packet as TcpRecvAckPacket),
      TcpPacketType.ping || TcpPacketType.pong => Uint8List(0),
      _ => throw UnsupportedError('Unsupported packet ${packet.packetType}'),
    };
    return Uint8List.fromList([..._encodeHeader(packet, body.length), ...body]);
  }

  TcpPacket decode(Uint8List data) {
    final reader = TcpReadData(data);
    final header = decodeHeader(reader);
    if (header.packetType == TcpPacketType.ping) {
      return TcpPingPacket()..header = header;
    }
    if (header.packetType == TcpPacketType.pong) {
      return TcpPongPacket()..header = header;
    }
    return switch (header.packetType) {
      TcpPacketType.connack => _decodeConnack(header, reader),
      TcpPacketType.recv => _decodeRecv(header, reader),
      TcpPacketType.sendack => _decodeSendAck(header, reader),
      TcpPacketType.disconnect => _decodeDisconnect(header, reader),
      _ => throw UnsupportedError('Unsupported packet ${header.packetType}'),
    };
  }

  static TcpPacketHeader decodeHeader(TcpReadData reader) {
    final byte = reader.readByte();
    final header = TcpPacketHeader()
      ..noPersist = (byte & 0x01) > 0
      ..showUnread = (byte >> 1 & 0x01) > 0
      ..syncOnce = (byte >> 2 & 0x01) > 0
      ..packetType = TcpPacketType.values[byte >> 4];
    if (header.packetType != TcpPacketType.ping &&
        header.packetType != TcpPacketType.pong) {
      header.remainingLength = reader.readVariableLength();
    }
    if (header.packetType == TcpPacketType.connack) {
      header.hasServerVersion = (byte & 0x01) > 0;
    }
    return header;
  }

  static int frameLength(Uint8List buffer) {
    if (buffer.isEmpty) {
      return 0;
    }
    final packetType = TcpPacketType.values[buffer[0] >> 4];
    if (packetType == TcpPacketType.ping || packetType == TcpPacketType.pong) {
      return 1;
    }
    var multiplier = 1;
    var value = 0;
    var offset = 1;
    var encodedByte = 0;
    do {
      if (offset >= buffer.length) {
        return 0;
      }
      encodedByte = buffer[offset++];
      value += (encodedByte & 127) * multiplier;
      multiplier *= 128;
      if (multiplier > 128 * 128 * 128) {
        throw const FormatException('Invalid TCP IM remaining length');
      }
    } while ((encodedByte & 128) != 0);
    return offset + value;
  }

  List<int> _encodeHeader(TcpPacket packet, int remainingLength) {
    final type = packet.packetType.index << 4;
    if (packet.packetType == TcpPacketType.ping ||
        packet.packetType == TcpPacketType.pong) {
      return [type];
    }
    final flags =
        (_bool(packet.header.syncOnce) << 2) |
        (_bool(packet.header.showUnread) << 1) |
        _bool(packet.header.noPersist);
    return [type | flags, ..._encodeVariableLength(remainingLength)];
  }

  Uint8List _encodeConnect(TcpConnectPacket packet) {
    final write = TcpWriteData()
      ..writeUint8(packet.version)
      ..writeUint8(packet.deviceFlag)
      ..writeString(packet.deviceId)
      ..writeString(packet.uid)
      ..writeString(packet.token)
      ..writeUint64(BigInt.from(packet.clientTimestamp))
      ..writeString(packet.clientKey);
    return write.toUint8List();
  }

  Uint8List _encodeRecvAck(TcpRecvAckPacket packet) {
    final write = TcpWriteData()
      ..writeUint64(packet.messageId)
      ..writeUint32(packet.messageSeq);
    return write.toUint8List();
  }

  TcpConnackPacket _decodeConnack(TcpPacketHeader header, TcpReadData reader) {
    final packet = TcpConnackPacket()..header = header;
    if (header.hasServerVersion) {
      packet.serviceProtoVersion = min(reader.readByte(), protoVersion);
      negotiatedProtoVersion = packet.serviceProtoVersion;
    } else {
      packet.serviceProtoVersion = protoVersion;
      negotiatedProtoVersion = protoVersion;
    }
    packet
      ..timeDiff = reader.readUint64().toInt()
      ..reasonCode = reader.readUint8()
      ..serverKey = reader.readString()
      ..salt = reader.readString();
    if (packet.serviceProtoVersion >= 4) {
      packet.nodeId = reader.readUint64().toInt();
    }
    return packet;
  }

  TcpSendAckPacket _decodeSendAck(TcpPacketHeader header, TcpReadData reader) {
    final packet = TcpSendAckPacket()..header = header;
    packet
      ..messageId = reader.readUint64().toString()
      ..clientSeq = reader.readUint32()
      ..messageSeq = reader.readUint32()
      ..reasonCode = reader.readUint8();
    return packet;
  }

  TcpRecvPacket _decodeRecv(TcpPacketHeader header, TcpReadData reader) {
    final packet = TcpRecvPacket()..header = header;
    packet
      ..setting = TcpSetting().decode(reader.readUint8())
      ..msgKey = reader.readString()
      ..fromUid = reader.readString()
      ..channelId = reader.readString()
      ..channelType = reader.readUint8();
    if (negotiatedProtoVersion >= 3) {
      packet.expire = reader.readUint32();
    }
    packet.clientMsgNo = reader.readString();
    if (packet.setting.stream == 1) {
      packet
        ..streamNo = reader.readString()
        ..streamSeq = reader.readUint32()
        ..streamFlag = reader.readByte();
    }
    packet
      ..messageId = reader.readUint64()
      ..messageSeq = reader.readUint32()
      ..messageTime = reader.readUint32();
    if (packet.setting.topic == 1) {
      packet.topic = reader.readString();
    }
    packet.payload = String.fromCharCodes(reader.readRemaining());
    return packet;
  }

  TcpDisconnectPacket _decodeDisconnect(
    TcpPacketHeader header,
    TcpReadData reader,
  ) {
    final packet = TcpDisconnectPacket()..header = header;
    packet
      ..reasonCode = reader.readUint8()
      ..reason = reader.readString();
    return packet;
  }

  int _bool(bool value) => value ? 1 : 0;

  List<int> _encodeVariableLength(int length) {
    if (length == 0) {
      return [0];
    }
    final result = <int>[];
    var value = length;
    while (value > 0) {
      var digit = value % 128;
      value = value ~/ 128;
      if (value > 0) {
        digit |= 128;
      }
      result.add(digit);
    }
    return result;
  }
}

class TcpReadData {
  TcpReadData(this._data) : _byteData = ByteData.view(_data.buffer);

  final Uint8List _data;
  final ByteData _byteData;
  int offset = 0;

  int readByte() => _data[offset++];

  int readUint8() => _byteData.getUint8(offset++);

  int readUint16() {
    final value = _byteData.getUint16(offset);
    offset += 2;
    return value;
  }

  int readUint32() {
    final value = _byteData.getUint32(offset);
    offset += 4;
    return value;
  }

  BigInt readUint64() {
    final data = _data.sublist(offset, offset + 8);
    offset += 8;
    var value = BigInt.zero;
    for (var i = 0; i < data.length; i++) {
      value += BigInt.from(data[i]) << ((data.length - i - 1) * 8);
    }
    return value;
  }

  String readString() {
    final length = readUint16();
    if (length <= 0) {
      return '';
    }
    final data = _data.sublist(offset, offset + length);
    offset += length;
    return utf8.decode(data);
  }

  Uint8List readRemaining() {
    final data = _data.sublist(offset);
    offset = _data.length;
    return data;
  }

  int readVariableLength() {
    var multiplier = 0;
    var length = 0;
    while (multiplier < 27) {
      final byte = readUint8();
      length |= (byte & 127) << multiplier;
      if ((byte & 128) == 0) {
        break;
      }
      multiplier += 7;
    }
    return length;
  }
}

class TcpWriteData {
  final data = <int>[];

  void writeUint8(int value) => data.add(value & 0xff);

  void writeUint16(int value) {
    data
      ..add((value >> 8) & 0xff)
      ..add(value & 0xff);
  }

  void writeUint32(int value) {
    data
      ..add((value >> 24) & 0xff)
      ..add((value >> 16) & 0xff)
      ..add((value >> 8) & 0xff)
      ..add(value & 0xff);
  }

  void writeUint64(BigInt value) {
    final high = (value ~/ BigInt.from(4294967296)).toInt();
    final low = (value % BigInt.from(4294967296)).toInt();
    writeUint32(high);
    writeUint32(low);
  }

  void writeString(String value) {
    if (value.isEmpty) {
      writeUint16(0);
      return;
    }
    final bytes = utf8.encode(value);
    writeUint16(bytes.length);
    data.addAll(bytes);
  }

  Uint8List toUint8List() => Uint8List.fromList(data);
}
