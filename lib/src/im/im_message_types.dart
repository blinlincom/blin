class ImMessageTypes {
  const ImMessageTypes._();

  static const text = 1;
  static const image = 2;
  static const voice = 3;
  static const video = 4;
  static const file = 5;
  static const command = 99;

  static const recall = 1006;
  static const transfer = 5101;
  static const redPacket = 5102;
  static const redPacketReceived = 5103;
  static const transferReceived = 5104;
  static const emoji = 5201;
  static const gif = 5202;
  static const sticker = 5203;
  static const contactCard = 5207;

  static const supported = <int>[
    text,
    image,
    voice,
    video,
    file,
    recall,
    transfer,
    redPacket,
    redPacketReceived,
    transferReceived,
    emoji,
    gif,
    sticker,
    contactCard,
  ];
}

class ChatContentTypes {
  const ChatContentTypes._();

  static const text = 'text';
  static const image = 'image';
  static const emoji = 'emoji';
  static const gif = 'gif';
  static const sticker = 'sticker';
  static const voice = 'voice';
  static const video = 'video';
  static const file = 'file';
  static const contactCard = 'contact_card';
  static const transfer = 'transfer';
  static const redPacket = 'red_packet';
}
