import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Delete,
  UseGuards,
  ParseIntPipe,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { ChatService } from './chat.service';
import { CreateMessageDto } from './dto/create-message.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';

@ApiTags('Chat')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('chat')
export class ChatController {
  constructor(private readonly chatService: ChatService) {}

  @Post()
  @ApiOperation({ summary: 'Отправить сообщение' })
  async create(
    @Body() dto: CreateMessageDto,
    @CurrentUser() user: { id: number; role: string },
  ) {
    // Пользователь может отправлять только от своего имени
    if (user.role !== 'admin') {
      dto.userId = user.id;
    }
    return this.chatService.create(dto);
  }

  @Get()
  @UseGuards(RolesGuard)
  @Roles('admin')
  @ApiOperation({ summary: 'Получить все сообщения (только admin)' })
  async findAll() {
    return this.chatService.findAll();
  }

  @Get('my')
  @ApiOperation({ summary: 'Получить свои сообщения' })
  async findMy(@CurrentUser() user: { id: number }) {
    return this.chatService.findByUser(user.id);
  }

  @Get('user/:userId')
  @UseGuards(RolesGuard)
  @Roles('admin')
  @ApiOperation({ summary: 'Получить сообщения пользователя (только admin)' })
  async findByUser(@Param('userId', ParseIntPipe) userId: number) {
    return this.chatService.findByUser(userId);
  }

  @Delete(':id')
  @UseGuards(RolesGuard)
  @Roles('admin')
  @ApiOperation({ summary: 'Удалить сообщение (только admin)' })
  async remove(
    @Param('id', ParseIntPipe) id: number,
    @CurrentUser() user: { id: number; role: string },
  ) {
    return this.chatService.remove(id, user.id, user.role);
  }
}