import { Module } from '@nestjs/common';
import { CallService } from './call.service';
import { CallGateway } from './call.gateway';
import { CallController } from './call.controller';
import { PrismaModule } from '../prisma/prisma.module';
import { AuthModule } from '../auth/auth.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { ChatModule } from '../chat/chat.module';

@Module({
  imports: [PrismaModule, AuthModule, NotificationsModule, ChatModule],
  controllers: [CallController],
  providers: [CallService, CallGateway],
  exports: [CallService],
})
export class CallModule {}