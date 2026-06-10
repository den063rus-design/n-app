import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { jwtConstants } from '../config/constants';
import { AuthService } from './auth.service';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(private readonly authService: AuthService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: jwtConstants.secret,
    });
  }

  async validate(payload: { sub: number; login: string; role: Role }) {
    const user = await this.authService.validateUser(payload.sub);

    if (!user) {
      return null;
    }

    return {
      id: user.id,
      fio: user.fio,
      age: user.age,
      login: user.login,
      role: user.role,
      status: user.status,
    };
  }
}
