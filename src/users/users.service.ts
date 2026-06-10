import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { Role, UserStatus } from '@prisma/client';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../prisma/prisma.service';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  private readonly userSelect = {
    id: true,
    fio: true,
    age: true,
    login: true,
    role: true,
    status: true,
    createdAt: true,
    updatedAt: true,
  } as const;

  async create(dto: CreateUserDto) {
    const existing = await this.prisma.user.findUnique({
      where: { login: dto.login },
    });

    if (existing) {
      throw new ConflictException('Пользователь с таким логином уже существует');
    }

    const passwordHash = await bcrypt.hash(dto.password, 10);

    return this.prisma.user.create({
      data: {
        fio: dto.fio,
        age: dto.age,
        login: dto.login,
        passwordHash,
        role: dto.role ?? Role.USER,
        status: UserStatus.ACTIVE,
      },
      select: this.userSelect,
    });
  }

  async findAll() {
    return this.prisma.user.findMany({
      orderBy: { createdAt: 'desc' },
      select: this.userSelect,
    });
  }

  async findOne(id: number) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      select: this.userSelect,
    });

    if (!user) {
      throw new NotFoundException('Пользователь не найден');
    }

    return user;
  }

  async update(id: number, dto: UpdateUserDto) {
    const user = await this.prisma.user.findUnique({
      where: { id },
    });

    if (!user) {
      throw new NotFoundException('Пользователь не найден');
    }

    if (dto.login && dto.login !== user.login) {
      const existing = await this.prisma.user.findUnique({
        where: { login: dto.login },
      });

      if (existing) {
        throw new ConflictException('Пользователь с таким логином уже существует');
      }
    }

    const data: {
      fio?: string;
      age?: number;
      login?: string;
      passwordHash?: string;
      role?: Role;
    } = {};

    if (dto.fio !== undefined) data.fio = dto.fio;
    if (dto.age !== undefined) data.age = dto.age;
    if (dto.login !== undefined) data.login = dto.login;
    if (dto.role !== undefined) data.role = dto.role;
    if (dto.password !== undefined) {
      data.passwordHash = await bcrypt.hash(dto.password, 10);
    }

    return this.prisma.user.update({
      where: { id },
      data,
      select: this.userSelect,
    });
  }

  async block(id: number) {
    return this.setStatus(id, UserStatus.BLOCKED);
  }

  async unblock(id: number) {
    return this.setStatus(id, UserStatus.ACTIVE);
  }

  async archive(id: number) {
    return this.setStatus(id, UserStatus.ARCHIVED);
  }

  async restore(id: number) {
    return this.setStatus(id, UserStatus.ACTIVE);
  }

  private async setStatus(id: number, status: UserStatus) {
    const user = await this.prisma.user.findUnique({
      where: { id },
    });

    if (!user) {
      throw new NotFoundException('Пользователь не найден');
    }

    return this.prisma.user.update({
      where: { id },
      data: { status },
      select: this.userSelect,
    });
  }
}
