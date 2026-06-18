import {
  Controller,
  Post,
  Body,
  UseGuards,
  HttpCode,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { LiveKitService } from './livekit.service';
import type { CurrentUserType } from './livekit.service';

class GetTokenDto {
  callId!: number;
}

@Controller('livekit')
@UseGuards(JwtAuthGuard)
export class LiveKitController {
  private readonly logger = new Logger(LiveKitController.name);

  constructor(private readonly liveKitService: LiveKitService) {}

  /**
   * POST /livekit/token
   *
   * Выдаёт LiveKit AccessToken для участника звонка.
   *
   * Тело запроса:
   * {
   *   "callId": 123
   * }
   *
   * Ответ:
   * {
   *   "wsUrl": "wss://livekit.natalie-eng.ru",
   *   "roomName": "call_123",
   *   "token": "..."
   * }
   */
  @Post('token')
  @HttpCode(HttpStatus.OK)
  async getToken(
    @Body() dto: GetTokenDto,
    @CurrentUser() user: CurrentUserType,
  ) {
    this.logger.log(
      `[LIVEKIT_CONTROLLER] token request userId=${user.id} callId=${dto.callId} dto=${JSON.stringify(dto)}`,
    );
    try {
      const result = await this.liveKitService.createTokenForCall(dto.callId, user);
      this.logger.log(
        `[LIVEKIT_CONTROLLER] token success userId=${user.id} callId=${dto.callId} roomName=${result.roomName}`,
      );
      return result;
    } catch (error) {
      this.logger.error(
        `[LIVEKIT_CONTROLLER] token error userId=${user.id} callId=${dto.callId} name=${(error as Error).name} message=${(error as Error).message} stack=${(error as Error).stack}`,
      );
      throw error;
    }
  }
}