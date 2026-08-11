import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Role, UserStatus } from '@prisma/client';

export class UserResponseDto {
  @ApiProperty()
  id!: number;

  @ApiProperty()
  fio!: string;

  @ApiProperty()
  age!: number | null;

  @ApiProperty()
  login!: string;

  @ApiProperty({ enum: Role })
  role!: Role;

  @ApiProperty({ enum: UserStatus })
  status!: UserStatus;

  @ApiPropertyOptional()
  notes!: string | null;

  @ApiProperty()
  isOnline!: boolean;

  @ApiPropertyOptional()
  lastSeenAt!: string | null;

  @ApiProperty()
  createdAt!: Date;

  @ApiProperty()
  updatedAt!: Date;
}
