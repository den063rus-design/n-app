import { Module } from '@nestjs/common';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { ChatModule } from './chat/chat.module';
import { FilesModule } from './files/files.module';
import { CallModule } from './call/call.module';
import { NotificationsModule } from './notifications/notifications.module';
import { PushModule } from './push/push.module';

@Module({
  imports: [
    PrismaModule,
    AuthModule,
    UsersModule,
    ChatModule,
    FilesModule,
    CallModule,
    NotificationsModule,
    PushModule,
  ],
  controllers: [],
  providers: [],
})
export class AppModule {}
