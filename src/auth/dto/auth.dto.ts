import { ApiProperty } from '@nestjs/swagger';
import { Role, UserStatus } from '@prisma/client';
import { IsString, MinLength } from 'class-validator';

export class LoginDto {
  @ApiProperty({ example: 'admin' })
  @IsString()
  @MinLength(3)
  login!: string;

  @ApiProperty({ example: 'password123' })
  @IsString()
  @MinLength(6)
  password!: string;
}

export class AuthResponseDto {
  @ApiProperty({ example: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...' })
  accessToken!: string;

  @ApiProperty({
    example: {
      id: 1,
      fio: 'Иван Иванов',
      age: 28,
      login: 'admin',
      role: 'ADMIN',
      status: 'ACTIVE',
    },
  })
  user!: {
    id: number;
    fio: string;
    age: number;
    login: string;
    role: Role;
    status: UserStatus;
  };
}
