import { Module } from '@nestjs/common';
import { LiveKitService } from './livekit.service';
import { LiveKitController } from './livekit.controller';
import { CallModule } from '../call/call.module';
import { AuthModule } from '../auth/auth.module';

@Module({
  imports: [CallModule, AuthModule],
  controllers: [LiveKitController],
  providers: [LiveKitService],
  exports: [LiveKitService],
})
export class LiveKitModule {}