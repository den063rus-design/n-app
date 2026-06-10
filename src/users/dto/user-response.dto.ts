import { ApiProperty } from '@nestjs/swagger';
import { Role, UserStatus } from '@prisma/client';

export class UserResponseDto {
  @ApiProperty()
  id!: number;

  @ApiProperty()
  fio!: string;

  @ApiProperty()
  age!: number;

  @ApiProperty()
  login!: string;

  @ApiProperty({ enum: Role })
  role!: Role;

  @ApiProperty({ enum: UserStatus })
  status!: UserStatus;

  @ApiProperty()
  createdAt!: Date;

  @ApiProperty()
  updatedAt!: Date;
}
