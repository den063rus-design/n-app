import { Body, Controller, Get, Param, ParseIntPipe, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { CreateMessageDto } from './dto/create-message.dto';
import { ChatService } from './chat.service';
import { Role } from '@prisma/client';

@ApiTags('Chat')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('chat')
export class ChatController {
  constructor(private readonly chatService: ChatService) {}

  @Post()
  @ApiOperation({ summary: 'Отправить сообщение' })
  async create(@Body() dto: CreateMessageDto, @CurrentUser() user: { id: number; role: Role }) {
    return this.chatService.createMessage(user.id, user.role, dto);
  }

  @Get('my')
  @ApiOperation({ summary: 'Получить свои сообщения' })
  async findMy(@CurrentUser() user: { id: number }) {
    return this.chatService.findByUser(user.id);
  }

  @Get()
  @UseGuards(RolesGuard)
  @Roles('ADMIN')
  @ApiOperation({ summary: 'Получить все сообщения' })
  async findAll() {
    return this.chatService.findAll();
  }

  @Get('user/:userId')
  @UseGuards(RolesGuard)
  @Roles('ADMIN')
  @ApiOperation({ summary: 'Получить сообщения пользователя' })
  async findByUser(@Param('userId', ParseIntPipe) userId: number) {
    return this.chatService.findByUser(userId);
  }
}
