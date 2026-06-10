import { Injectable, NotFoundException } from '@nestjs/common';
import { CallStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class CallService {
  constructor(private readonly prisma: PrismaService) {}

  async createCall(callerId: number, calleeId: number) {
    return this.prisma.call.create({
      data: {
        callerId,
        calleeId,
        status: CallStatus.PENDING,
      },
      include: {
        caller: { select: { id: true, fio: true } },
        callee: { select: { id: true, fio: true } },
      },
    });
  }

  async updateCallStatus(
    callId: number,
    status: CallStatus,
    startedAt?: Date,
    endedAt?: Date,
  ) {
    const call = await this.prisma.call.findUnique({ where: { id: callId } });
    if (!call) {
      throw new NotFoundException('Звонок не найден');
    }

    return this.prisma.call.update({
      where: { id: callId },
      data: {
        status,
        ...(startedAt !== undefined ? { startedAt } : {}),
        ...(endedAt !== undefined ? { endedAt } : {}),
      },
      include: {
        caller: { select: { id: true, fio: true } },
        callee: { select: { id: true, fio: true } },
      },
    });
  }

  async getUserCalls(userId: number) {
    return this.prisma.call.findMany({
      where: {
        OR: [{ callerId: userId }, { calleeId: userId }],
      },
      orderBy: { createdAt: 'desc' },
      include: {
        caller: { select: { id: true, fio: true } },
        callee: { select: { id: true, fio: true } },
      },
    });
  }

  async getCallById(callId: number) {
    const call = await this.prisma.call.findUnique({
      where: { id: callId },
      include: {
        caller: { select: { id: true, fio: true } },
        callee: { select: { id: true, fio: true } },
      },
    });

    if (!call) {
      throw new NotFoundException('Звонок не найден');
    }

    return call;
  }
}