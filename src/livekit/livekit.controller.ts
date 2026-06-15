import {
  Controller,
  Post,
  Body,
  UseGuards,
  HttpCode,
  HttpStatus,
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
    return this.liveKitService.createTokenForCall(dto.callId, user);
  }
}