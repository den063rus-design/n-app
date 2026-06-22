import { Controller, Get, Param, ParseIntPipe, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { CallService } from './call.service';

@Controller('call')
@UseGuards(JwtAuthGuard)
export class CallController {
  constructor(private readonly callService: CallService) {}

  @Get('my')
  async getMyCalls(@CurrentUser('sub') userId: number) {
    return this.callService.getUserCalls(userId);
  }

  @Get('history/:userId')
  @UseGuards(RolesGuard)
  @Roles('ADMIN')
  async getUserHistory(@Param('userId', ParseIntPipe) userId: number) {
    return this.callService.getUserCalls(userId);
  }

  @Get('ice-config')
  async getIceConfig(@CurrentUser('sub') userId: number) {
    return this.callService.getIceConfig(userId);
  }
}
