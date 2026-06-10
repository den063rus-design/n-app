import {
  Controller,
  Get,
  Patch,
  Param,
  Query,
  UseGuards,
  ParseIntPipe,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { NotificationsService } from './notifications.service';
import { NotificationsGateway } from './notifications.gateway';

@Controller('notifications')
@UseGuards(JwtAuthGuard)
export class NotificationsController {
  constructor(
    private readonly notificationsService: NotificationsService,
    private readonly notificationsGateway: NotificationsGateway,
  ) {}

  @Get('my')
  async getMyNotifications(
    @CurrentUser('sub') userId: number,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const pageNum = page ? parseInt(page, 10) : 1;
    const limitNum = limit ? parseInt(limit, 10) : 20;
    return this.notificationsService.getUserNotifications(userId, pageNum, limitNum);
  }

  @Patch(':id/read')
  async markAsRead(@Param('id', ParseIntPipe) id: number) {
    return this.notificationsService.markAsRead(id);
  }

  @Patch('read-all')
  async markAllAsRead(@CurrentUser('sub') userId: number) {
    await this.notificationsService.markAllAsRead(userId);
    const unreadCount = await this.notificationsService.getUnreadCount(userId);
    this.notificationsGateway.sendUnreadCount(userId, unreadCount);
    return { success: true };
  }

  @Get('unread-count')
  async getUnreadCount(@CurrentUser('sub') userId: number) {
    const count = await this.notificationsService.getUnreadCount(userId);
    return { count };
  }
}