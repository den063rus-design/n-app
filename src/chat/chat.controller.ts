import {
  Body,
  Controller,
  Delete,
  Patch,
  Get,
  Param,
  ParseIntPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiParam, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { CreateMessageDto } from './dto/create-message.dto';
import { ChatHistoryQueryDto } from './dto/chat-history-query.dto';
import { UpdateMessageDto } from './dto/update-message.dto';
import { ChatService } from './chat.service';
import { ChatGateway } from './chat.gateway';

@ApiTags('Chat')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('chat')
export class ChatController {
  constructor(
    private readonly chatService: ChatService,
    private readonly chatGateway: ChatGateway,
  ) {}

  @Post()
  @ApiOperation({ summary: 'Отправить сообщение' })
  async create(@Body() dto: CreateMessageDto, @CurrentUser() user: { id: number; role: string }) {
    if (user.role !== 'ADMIN') {
      dto.userId = user.id;
    }
    const message = await this.chatService.create(dto, user.id);
    return message;
  }

  @Get()
  @UseGuards(RolesGuard)
  @Roles('ADMIN')
  @ApiOperation({ summary: 'Получить все сообщения (только admin)' })
  async findAll() {
    return this.chatService.findAll();
  }

  @Get('my')
  @ApiOperation({ summary: 'Получить свои сообщения' })
  async findMy(@CurrentUser() user: { id: number }) {
    return this.chatService.findByUser(user.id);
  }

  @Get('history/:userId')
  @ApiOperation({ summary: 'Получить историю сообщений с пагинацией' })
  @ApiParam({ name: 'userId', type: Number })
  async getHistory(
    @Param('userId', ParseIntPipe) userId: number,
    @Query() query: ChatHistoryQueryDto,
    @CurrentUser() user: { id: number; role: string },
  ) {
    return this.chatService.getHistory(userId, query, user.id, user.role);
  }

  @Get('user/:userId')
  @UseGuards(RolesGuard)
  @Roles('ADMIN')
  @ApiOperation({ summary: 'Получить сообщения пользователя (только admin)' })
  async findByUser(@Param('userId', ParseIntPipe) userId: number) {
    return this.chatService.findByUser(userId);
  }

  @Patch('message/:messageId')
  @ApiOperation({ summary: 'Редактировать сообщение' })
  async updateMessage(
    @Param('messageId', ParseIntPipe) messageId: number,
    @Body() dto: UpdateMessageDto,
    @CurrentUser() user: { id: number; role: string },
  ) {
    return this.chatService.updateMessage(messageId, dto, user.id, user.role);
  }

  @Delete(':id')
  @UseGuards(RolesGuard)
  @Roles('ADMIN')
  @ApiOperation({ summary: 'Удалить сообщение по ID (только admin)' })
  async remove(
    @Param('id', ParseIntPipe) id: number,
    @CurrentUser() user: { id: number; role: string },
  ) {
    const result = await this.chatService.deleteMessage(id, user.id, user.role);
    return result.response;
  }
}
