import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { MessageStatus, Role, UserStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ChatGateway } from './chat.gateway';
import { FilesService } from '../files/files.service';
import { NotificationsService } from '../notifications/notifications.service';
import { CreateMessageDto } from './dto/create-message.dto';
import { ChatHistoryQueryDto } from './dto/chat-history-query.dto';
import { UpdateMessageDto } from './dto/update-message.dto';

@Injectable()
export class ChatService {
  private readonly logger = new Logger(ChatService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly chatGateway: ChatGateway,
    private readonly filesService: FilesService,
    private readonly notificationsService: NotificationsService,
  ) {}

  private readonly messageSelect = {
    id: true,
    senderId: true,
    receiverId: true,
    text: true,
    status: true,
    createdAt: true,
    updatedAt: true,
    attachments: {
      select: {
        id: true,
        key: true,
        url: true,
        fileType: true,
        fileName: true,
        fileSize: true,
      },
    },
  } as const;

  async create(dto: CreateMessageDto, senderId: number) {
    const sender = await this.prisma.user.findUnique({
      where: { id: senderId },
    });

    if (!sender || sender.status !== UserStatus.ACTIVE) {
      throw new ForbiddenException('Р СџР С•Р В»РЎРЉР В·Р С•Р Р†Р В°РЎвЂљР ВµР В»РЎРЉ Р Р…Р ВµР Т‘Р С•РЎРѓРЎвЂљРЎС“Р С—Р ВµР Р…');
    }

    const receiver = await this.resolveReceiver(sender.role, dto.userId);

    if (sender.id === receiver.id) {
      throw new BadRequestException('Р СњР ВµР В»РЎРЉР В·РЎРЏ Р С•РЎвЂљР С—РЎР‚Р В°Р Р†Р С‘РЎвЂљРЎРЉ РЎРѓР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘Р Вµ РЎРѓР В°Р СР С•Р СРЎС“ РЎРѓР ВµР В±Р Вµ');
    }

    this.assertAdminUserChat(sender.role, receiver.role);

    // Р С›Р С—РЎР‚Р ВµР Т‘Р ВµР В»РЎРЏР ВµР С Р Р†Р В»Р С•Р В¶Р ВµР Р…Р С‘РЎРЏ: РЎРѓР Р…Р В°РЎвЂЎР В°Р В»Р В° Р С‘Р В· Р Р…Р С•Р Р†Р С•Р С–Р С• Р С—Р С•Р В»РЎРЏ files, Р В·Р В°РЎвЂљР ВµР С Р С‘Р В· РЎРѓРЎвЂљР В°РЎР‚Р С•Р С–Р С• fileKeys (Р Т‘Р В»РЎРЏ Р С•Р В±РЎР‚Р В°РЎвЂљР Р…Р С•Р в„– РЎРѓР С•Р Р†Р СР ВµРЎРѓРЎвЂљР С‘Р СР С•РЎРѓРЎвЂљР С‘)
    let attachmentsData: Array<{
      key: string;
      url: string;
      fileName: string;
      fileType: string;
      fileSize: number;
    }> = [];

    if (dto.files && dto.files.length > 0) {
      attachmentsData = dto.files.map((f) => ({
        key: f.key,
        url: this.filesService.getFileUrl(f.key),
        fileName: f.originalName,
        fileType: f.mimeType,
        fileSize: f.fileSize,
      }));
    } else if (dto.fileKeys && dto.fileKeys.length > 0) {
      // Р С›Р В±РЎР‚Р В°РЎвЂљР Р…Р В°РЎРЏ РЎРѓР С•Р Р†Р СР ВµРЎРѓРЎвЂљР С‘Р СР С•РЎРѓРЎвЂљРЎРЉ: fileKeys Р В±Р ВµР В· Р СР ВµРЎвЂљР В°Р Т‘Р В°Р Р…Р Р…РЎвЂ№РЎвЂ¦
      attachmentsData = dto.fileKeys.map((key) => {
        const ext = key.includes('.') ? key.split('.').pop()?.toLowerCase() : '';
        const fileType = this.getMimeTypeFromExtension(ext || '');
        return {
          key,
          url: this.filesService.getFileUrl(key),
          fileName: key,
          fileType,
          fileSize: 0,
        };
      });
    }

    const message = await this.prisma.message.create({
      data: {
        senderId: sender.id,
        receiverId: receiver.id,
        text: dto.text,
        status: MessageStatus.SENT,
        ...(attachmentsData.length > 0
          ? {
              attachments: {
                create: attachmentsData,
              },
            }
          : {}),
      },
      select: this.messageSelect,
    });

    // Р В­Р СР С‘РЎвЂљР С‘Р С РЎРѓР С•Р В±РЎвЂ№РЎвЂљР С‘Р Вµ РЎвЂЎР ВµРЎР‚Р ВµР В· gateway
    this.chatGateway.sendToChatParticipants(
      message.senderId,
      message.receiverId,
      'message:new',
      message,
    );

    // Р РЋР С•Р В·Р Т‘Р В°РЎвЂР С РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘Р Вµ Р Т‘Р В»РЎРЏ Р С—Р С•Р В»РЎС“РЎвЂЎР В°РЎвЂљР ВµР В»РЎРЏ (realtime-РЎРѓР С•Р В±РЎвЂ№РЎвЂљР С‘Р Вµ Р С•РЎвЂљР С—РЎР‚Р В°Р Р†Р В»РЎРЏР ВµРЎвЂљРЎРѓРЎРЏ Р Р†Р Р…РЎС“РЎвЂљРЎР‚Р С‘ createNotification)
    await this.notificationsService.createNotification({
      userId: message.receiverId,
      type: 'MESSAGE',
      title: 'Р СњР С•Р Р†Р С•Р Вµ РЎРѓР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘Р Вµ',
      body: message.text.substring(0, 100),
      data: {
        messageId: message.id,
        senderId: message.senderId,
        senderName: sender.fio,
      },
    });

    return message;
  }

  async getHistory(
    userId: number,
    query: ChatHistoryQueryDto,
    currentUserId: number,
    currentUserRole: string,
  ) {
    // Р вЂўРЎРѓР В»Р С‘ РЎР‚Р С•Р В»РЎРЉ USER РІР‚вЂќ Р С—РЎР‚Р С•Р Р†Р ВµРЎР‚РЎРЏР ВµР С, РЎвЂЎРЎвЂљР С• userId === currentUserId
    if (currentUserRole !== 'ADMIN' && userId !== currentUserId) {
      throw new ForbiddenException('Р вЂќР С•РЎРѓРЎвЂљРЎС“Р С— Р В·Р В°Р С—РЎР‚Р ВµРЎвЂ°РЎвЂР Р…');
    }

    const page = query.page ?? 1;
    const limit = query.limit ?? 50;
    const skip = (page - 1) * limit;

    const where = {
      OR: [
        { senderId: userId, receiverId: currentUserId },
        { senderId: currentUserId, receiverId: userId },
      ] as Array<{ senderId: number; receiverId: number }>,
    };

    const [data, total] = await Promise.all([
      this.prisma.message.findMany({
        where,
        orderBy: { createdAt: 'asc' },
        skip,
        take: limit,
        select: this.messageSelect,
      }),
      this.prisma.message.count({ where }),
    ]);

    return { data, total, page, limit };
  }

  async findAll() {
    return this.prisma.message.findMany({
      orderBy: { createdAt: 'asc' },
      select: this.messageSelect,
    });
  }

  async findByUser(userId: number) {
    return this.prisma.message.findMany({
      where: {
        OR: [{ senderId: userId }, { receiverId: userId }],
      },
      orderBy: { createdAt: 'asc' },
      select: this.messageSelect,
    });
  }

  async deleteMessage(messageId: number, currentUserId: number, currentUserRole: string) {
    if (currentUserRole !== 'ADMIN') {
      throw new ForbiddenException('Р СћР С•Р В»РЎРЉР С”Р С• Р В°Р Т‘Р СР С‘Р Р…Р С‘РЎРѓРЎвЂљРЎР‚Р В°РЎвЂљР С•РЎР‚ Р СР С•Р В¶Р ВµРЎвЂљ РЎС“Р Т‘Р В°Р В»РЎРЏРЎвЂљРЎРЉ РЎРѓР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘РЎРЏ');
    }

    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
      select: {
        ...this.messageSelect,
        sender: { select: { id: true } },
        receiver: { select: { id: true } },
      },
    });

    if (!message) {
      throw new NotFoundException('Р РЋР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘Р Вµ Р Р…Р Вµ Р Р…Р В°Р в„–Р Т‘Р ВµР Р…Р С•');
    }

    // Р Р€Р Т‘Р В°Р В»РЎРЏР ВµР С РЎвЂћР С‘Р В·Р С‘РЎвЂЎР ВµРЎРѓР С”Р С‘Р Вµ РЎвЂћР В°Р в„–Р В»РЎвЂ№ Р Р†Р В»Р С•Р В¶Р ВµР Р…Р С‘Р в„– Р С—Р ВµРЎР‚Р ВµР Т‘ РЎС“Р Т‘Р В°Р В»Р ВµР Р…Р С‘Р ВµР С РЎРѓР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘РЎРЏ Р С‘Р В· Р вЂР вЂќ
    if (message.attachments && message.attachments.length > 0) {
      for (const attachment of message.attachments) {
        try {
          await this.filesService.deleteFile(attachment.key);
        } catch (err) {
          // Р вЂўРЎРѓР В»Р С‘ РЎвЂћР В°Р в„–Р В» РЎС“Р В¶Р Вµ Р С•РЎвЂљРЎРѓРЎС“РЎвЂљРЎРѓРЎвЂљР Р†РЎС“Р ВµРЎвЂљ Р Р…Р В° Р Т‘Р С‘РЎРѓР С”Р Вµ РІР‚вЂќ РЎвЂљР С•Р В»РЎРЉР С”Р С• Р В»Р С•Р С–, Р Р…Р Вµ Р Р†Р В°Р В»Р С‘Р С Р В·Р В°Р С—РЎР‚Р С•РЎРѓ
          this.logger.warn(
            `Р СњР Вµ РЎС“Р Т‘Р В°Р В»Р С•РЎРѓРЎРЉ РЎС“Р Т‘Р В°Р В»Р С‘РЎвЂљРЎРЉ РЎвЂћР С‘Р В·Р С‘РЎвЂЎР ВµРЎРѓР С”Р С‘Р в„– РЎвЂћР В°Р в„–Р В» Р Р†Р В»Р С•Р В¶Р ВµР Р…Р С‘РЎРЏ ${attachment.id} (key: ${attachment.key}): ${(err as Error).message}`,
          );
        }
      }
    }

    await this.prisma.message.delete({
      where: { id: messageId },
    });

    // Р В­Р СР С‘РЎвЂљР С‘Р С РЎРѓР С•Р В±РЎвЂ№РЎвЂљР С‘Р Вµ РЎС“Р Т‘Р В°Р В»Р ВµР Р…Р С‘РЎРЏ Р С•Р В±Р С•Р С‘Р С РЎС“РЎвЂЎР В°РЎРѓРЎвЂљР Р…Р С‘Р С”Р В°Р С
    this.chatGateway.sendToChatParticipants(
      message.senderId,
      message.receiverId,
      'message:deleted',
      { messageId },
    );

    return {
      message: { senderId: message.senderId, receiverId: message.receiverId },
      response: { message: 'Р РЋР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘Р Вµ РЎС“Р Т‘Р В°Р В»Р ВµР Р…Р С•' },
    };
  }

  async updateMessage(
    messageId: number,
    dto: UpdateMessageDto,
    currentUserId: number,
    currentUserRole: string,
  ) {
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
    });

    if (!message) {
      throw new NotFoundException('Р РЋР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘Р Вµ Р Р…Р Вµ Р Р…Р В°Р в„–Р Т‘Р ВµР Р…Р С•');
    }

    if (currentUserRole !== 'ADMIN' && message.senderId !== currentUserId) {
      throw new ForbiddenException('Р СћР С•Р В»РЎРЉР С”Р С• Р В°Р Р†РЎвЂљР С•РЎР‚ РЎРѓР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘РЎРЏ Р С‘Р В»Р С‘ Р В°Р Т‘Р СР С‘Р Р… Р СР С•Р В¶Р ВµРЎвЂљ РЎР‚Р ВµР Т‘Р В°Р С”РЎвЂљР С‘РЎР‚Р С•Р Р†Р В°РЎвЂљРЎРЉ РЎРѓР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘Р Вµ');
    }

    const updated = await this.prisma.message.update({
      where: { id: messageId },
      data: { text: dto.text },
      select: this.messageSelect,
    });

    this.chatGateway.sendToChatParticipants(
      updated.senderId,
      updated.receiverId,
      'message:updated',
      updated,
    );

    return updated;
  }

  async markAsDelivered(messageId: number) {
    return this.updateStatus(messageId, MessageStatus.DELIVERED, 'message:delivered');
  }

  async markAsRead(messageId: number) {
    return this.updateStatus(messageId, MessageStatus.READ, 'message:read');
  }

  async remove(messageId: number, userId: number, userRole: string) {
    return this.deleteMessage(messageId, userId, userRole);
  }

  private async updateStatus(messageId: number, status: MessageStatus, event: string) {
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
    });

    if (!message) {
      throw new NotFoundException('Р РЋР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘Р Вµ Р Р…Р Вµ Р Р…Р В°Р в„–Р Т‘Р ВµР Р…Р С•');
    }

    const updated = await this.prisma.message.update({
      where: { id: messageId },
      data: { status },
      select: this.messageSelect,
    });

    // Р В­Р СР С‘РЎвЂљР С‘Р С РЎРѓР С•Р В±РЎвЂ№РЎвЂљР С‘Р Вµ Р С•Р В±Р С•Р С‘Р С РЎС“РЎвЂЎР В°РЎРѓРЎвЂљР Р…Р С‘Р С”Р В°Р С
    this.chatGateway.sendToChatParticipants(updated.senderId, updated.receiverId, event, updated);

    return updated;
  }

  private async resolveReceiver(senderRole: Role, receiverId?: number) {
    if (senderRole === Role.ADMIN) {
      if (!receiverId) {
        throw new BadRequestException('Р вЂќР В»РЎРЏ Р В°Р Т‘Р СР С‘Р Р…Р С‘РЎРѓРЎвЂљРЎР‚Р В°РЎвЂљР С•РЎР‚Р В° Р Р…Р ВµР С•Р В±РЎвЂ¦Р С•Р Т‘Р С‘Р СР С• РЎС“Р С”Р В°Р В·Р В°РЎвЂљРЎРЉ Р С—Р С•Р В»РЎС“РЎвЂЎР В°РЎвЂљР ВµР В»РЎРЏ');
      }

      const receiver = await this.prisma.user.findUnique({
        where: { id: receiverId },
      });

      if (!receiver) {
        throw new NotFoundException('Р СџР С•Р В»РЎС“РЎвЂЎР В°РЎвЂљР ВµР В»РЎРЉ Р Р…Р Вµ Р Р…Р В°Р в„–Р Т‘Р ВµР Р…');
      }

      if (receiver.status !== UserStatus.ACTIVE) {
        throw new BadRequestException('Р СџР С•Р В»РЎС“РЎвЂЎР В°РЎвЂљР ВµР В»РЎРЉ Р Р…Р ВµР Т‘Р С•РЎРѓРЎвЂљРЎС“Р С—Р ВµР Р…');
      }

      return receiver;
    }

    const admin = await this.prisma.user.findFirst({
      where: {
        role: Role.ADMIN,
        status: UserStatus.ACTIVE,
      },
      orderBy: { createdAt: 'asc' },
    });

    if (!admin) {
      throw new NotFoundException('Р С’Р С”РЎвЂљР С‘Р Р†Р Р…РЎвЂ№Р в„– Р В°Р Т‘Р СР С‘Р Р…Р С‘РЎРѓРЎвЂљРЎР‚Р В°РЎвЂљР С•РЎР‚ Р Р…Р Вµ Р Р…Р В°Р в„–Р Т‘Р ВµР Р…');
    }

    return admin;
  }

  private getMimeTypeFromExtension(ext: string): string {
    const mimeMap: Record<string, string> = {
      jpg: 'image/jpeg',
      jpeg: 'image/jpeg',
      png: 'image/png',
      gif: 'image/gif',
      webp: 'image/webp',
      bmp: 'image/bmp',
      heic: 'image/heic',
      mp4: 'video/mp4',
      mov: 'video/quicktime',
      mkv: 'video/x-matroska',
      webm: 'video/webm',
      avi: 'video/x-msvideo',
      mp3: 'audio/mpeg',
      wav: 'audio/wav',
      m4a: 'audio/mp4',
      aac: 'audio/aac',
      ogg: 'audio/ogg',
      flac: 'audio/flac',
      pdf: 'application/pdf',
      doc: 'application/msword',
      docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      xls: 'application/vnd.ms-excel',
      xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      zip: 'application/zip',
      rar: 'application/vnd.rar',
    };
    return mimeMap[ext] || 'application/octet-stream';
  }

  private assertAdminUserChat(senderRole: Role, receiverRole: Role) {
    const validPair =
      (senderRole === Role.ADMIN && receiverRole === Role.USER) ||
      (senderRole === Role.USER && receiverRole === Role.ADMIN);

    if (!validPair) {
      throw new BadRequestException('Р В§Р В°РЎвЂљ Р Т‘Р С•РЎРѓРЎвЂљРЎС“Р С—Р ВµР Р… РЎвЂљР С•Р В»РЎРЉР С”Р С• Р СР ВµР В¶Р Т‘РЎС“ Р С—Р С•Р В»РЎРЉР В·Р С•Р Р†Р В°РЎвЂљР ВµР В»Р ВµР С Р С‘ Р В°Р Т‘Р СР С‘Р Р…Р С‘РЎРѓРЎвЂљРЎР‚Р В°РЎвЂљР С•РЎР‚Р С•Р С');
    }
  }
}
