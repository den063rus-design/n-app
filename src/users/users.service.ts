import {
  ConflictException,
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { Prisma, UserStatus } from '@prisma/client';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../prisma/prisma.service';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import { UpdateCredentialsDto } from './dto/update-credentials.dto';
import { QueryUsersDto } from './dto/query-users.dto';

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
        role: dto.role ?? 'USER',
        status: UserStatus.ACTIVE,
      },
      select: this.userSelect,
    });
  }

  async findAll(query: QueryUsersDto) {
    const { search, sort, order, status } = query;

    const where: Record<string, unknown> = {};

    if (search) {
      where.fio = {
        contains: search,
        mode: 'insensitive' as const,
      };
    }

    if (status) {
      where.status = status;
    }

    let orderBy: Record<string, string> = { createdAt: 'asc' };

    if (sort) {
      const sortFieldMap: Record<string, string> = {
        name: 'fio',
        age: 'age',
        created: 'createdAt',
      };

      orderBy = {
        [sortFieldMap[sort] || 'createdAt']: order || 'asc',
      };
    } else if (order) {
      orderBy = { createdAt: order };
    }

    return this.prisma.user.findMany({
      where,
      orderBy,
      select: this.userSelect,
    });
  }

  async findArchived() {
    return this.prisma.user.findMany({
      where: { status: UserStatus.ARCHIVED },
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
    } = {};

    if (dto.fio !== undefined) data.fio = dto.fio;
    if (dto.age !== undefined) data.age = dto.age;
    if (dto.login !== undefined) data.login = dto.login;

    return this.prisma.user.update({
      where: { id },
      data,
      select: this.userSelect,
    });
  }

  async updateCredentials(id: number, dto: UpdateCredentialsDto) {
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
      login?: string;
      passwordHash?: string;
    } = {};

    if (dto.login !== undefined) data.login = dto.login;
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

  async remove(id: number) {
    const user = await this.prisma.user.findUnique({
      where: { id },
    });

    if (!user) {
      throw new NotFoundException('Пользователь не найден');
    }

    if (user.status !== UserStatus.ARCHIVED) {
      throw new BadRequestException('Можно удалить только архивного пользователя');
    }

    return this.prisma.$transaction(async (tx: Prisma.TransactionClient) => {
      await tx.message.deleteMany({
        where: {
          OR: [{ senderId: id }, { receiverId: id }],
        },
      });

      await tx.user.delete({
        where: { id },
      });

      return { message: 'Пользователь и его сообщения удалены' };
    });
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
