import {
  BadRequestException,
  ForbiddenException,
  Injectable,
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
      throw new ForbiddenException('РџРѕР»СЊР·РѕРІР°С‚РµР»СЊ РЅРµРґРѕСЃС‚СѓРїРµРЅ');
    }

    const receiver = await this.resolveReceiver(sender.role, dto.userId);

    if (sender.id === receiver.id) {
      throw new BadRequestException('РќРµР»СЊР·СЏ РѕС‚РїСЂР°РІРёС‚СЊ СЃРѕРѕР±С‰РµРЅРёРµ СЃР°РјРѕРјСѓ СЃРµР±Рµ');
    }

    this.assertAdminUserChat(sender.role, receiver.role);

    // РћРїСЂРµРґРµР»СЏРµРј РІР»РѕР¶РµРЅРёСЏ: СЃРЅР°С‡Р°Р»Р° РёР· РЅРѕРІРѕРіРѕ РїРѕР»СЏ files, Р·Р°С‚РµРј РёР· СЃС‚Р°СЂРѕРіРѕ fileKeys (РґР»СЏ РѕР±СЂР°С‚РЅРѕР№ СЃРѕРІРјРµСЃС‚РёРјРѕСЃС‚Рё)
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
      // РћР±СЂР°С‚РЅР°СЏ СЃРѕРІРјРµСЃС‚РёРјРѕСЃС‚СЊ: fileKeys Р±РµР· РјРµС‚Р°РґР°РЅРЅС‹С…
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

    // Р­РјРёС‚РёРј СЃРѕР±С‹С‚РёРµ С‡РµСЂРµР· gateway
    this.chatGateway.sendToChatParticipants(
      message.senderId,
      message.receiverId,
      'message:new',
      message,
    );

    // РЎРѕР·РґР°С‘Рј СѓРІРµРґРѕРјР»РµРЅРёРµ РґР»СЏ РїРѕР»СѓС‡Р°С‚РµР»СЏ (realtime-СЃРѕР±С‹С‚РёРµ РѕС‚РїСЂР°РІР»СЏРµС‚СЃСЏ РІРЅСѓС‚СЂРё createNotification)
    await this.notificationsService.createNotification({
      userId: message.receiverId,
      type: 'MESSAGE',
      title: 'РќРѕРІРѕРµ СЃРѕРѕР±С‰РµРЅРёРµ',
      body: message.text.substring(0, 100),
      data: { messageId: message.id, senderId: message.senderId },
    });

    return message;
  }

  async getHistory(
    userId: number,
    query: ChatHistoryQueryDto,
    currentUserId: number,
    currentUserRole: string,
  ) {
    // Р•СЃР»Рё СЂРѕР»СЊ USER вЂ” РїСЂРѕРІРµСЂСЏРµРј, С‡С‚Рѕ userId === currentUserId
    if (currentUserRole !== 'ADMIN' && userId !== currentUserId) {
      throw new ForbiddenException('Р”РѕСЃС‚СѓРї Р·Р°РїСЂРµС‰С‘РЅ');
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
      throw new ForbiddenException('РўРѕР»СЊРєРѕ Р°РґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂ РјРѕР¶РµС‚ СѓРґР°Р»СЏС‚СЊ СЃРѕРѕР±С‰РµРЅРёСЏ');
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
      throw new NotFoundException('РЎРѕРѕР±С‰РµРЅРёРµ РЅРµ РЅР°Р№РґРµРЅРѕ');
    }

    await this.prisma.message.delete({
      where: { id: messageId },
    });

    // Р­РјРёС‚РёРј СЃРѕР±С‹С‚РёРµ СѓРґР°Р»РµРЅРёСЏ РѕР±РѕРёРј СѓС‡Р°СЃС‚РЅРёРєР°Рј
    this.chatGateway.sendToChatParticipants(
      message.senderId,
      message.receiverId,
      'message:deleted',
      { messageId },
    );

    return {
      message: { senderId: message.senderId, receiverId: message.receiverId },
      response: { message: 'РЎРѕРѕР±С‰РµРЅРёРµ СѓРґР°Р»РµРЅРѕ' },
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
      throw new NotFoundException('Сообщение не найдено');
    }

    if (currentUserRole !== 'ADMIN' && message.senderId !== currentUserId) {
      throw new ForbiddenException('Только автор сообщения или админ может редактировать сообщение');
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
      throw new NotFoundException('РЎРѕРѕР±С‰РµРЅРёРµ РЅРµ РЅР°Р№РґРµРЅРѕ');
    }

    const updated = await this.prisma.message.update({
      where: { id: messageId },
      data: { status },
      select: this.messageSelect,
    });

    // Р­РјРёС‚РёРј СЃРѕР±С‹С‚РёРµ РѕР±РѕРёРј СѓС‡Р°СЃС‚РЅРёРєР°Рј
    this.chatGateway.sendToChatParticipants(updated.senderId, updated.receiverId, event, updated);

    return updated;
  }

  private async resolveReceiver(senderRole: Role, receiverId?: number) {
    if (senderRole === Role.ADMIN) {
      if (!receiverId) {
        throw new BadRequestException('Р”Р»СЏ Р°РґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂР° РЅРµРѕР±С…РѕРґРёРјРѕ СѓРєР°Р·Р°С‚СЊ РїРѕР»СѓС‡Р°С‚РµР»СЏ');
      }

      const receiver = await this.prisma.user.findUnique({
        where: { id: receiverId },
      });

      if (!receiver) {
        throw new NotFoundException('РџРѕР»СѓС‡Р°С‚РµР»СЊ РЅРµ РЅР°Р№РґРµРЅ');
      }

      if (receiver.status !== UserStatus.ACTIVE) {
        throw new BadRequestException('РџРѕР»СѓС‡Р°С‚РµР»СЊ РЅРµРґРѕСЃС‚СѓРїРµРЅ');
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
      throw new NotFoundException('РђРєС‚РёРІРЅС‹Р№ Р°РґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂ РЅРµ РЅР°Р№РґРµРЅ');
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
      throw new BadRequestException('Р§Р°С‚ РґРѕСЃС‚СѓРїРµРЅ С‚РѕР»СЊРєРѕ РјРµР¶РґСѓ РїРѕР»СЊР·РѕРІР°С‚РµР»РµРј Рё Р°РґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂРѕРј');
    }
  }
}
