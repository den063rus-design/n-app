import { Body, Controller, Get, Param, ParseIntPipe, Patch, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import { UsersService } from './users.service';

@ApiTags('Users')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('ADMIN')
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Post()
  @ApiOperation({ summary: 'Создать пользователя' })
  async create(@Body() dto: CreateUserDto) {
    return this.usersService.create(dto);
  }

  @Get()
  @ApiOperation({ summary: 'Получить список пользователей' })
  async findAll() {
    return this.usersService.findAll();
  }

  @Get(':id')
  @ApiOperation({ summary: 'Получить пользователя по ID' })
  async findOne(@Param('id', ParseIntPipe) id: number) {
    return this.usersService.findOne(id);
  }

  @Patch(':id')
  @ApiOperation({ summary: 'Обновить пользователя' })
  async update(@Param('id', ParseIntPipe) id: number, @Body() dto: UpdateUserDto) {
    return this.usersService.update(id, dto);
  }

  @Patch(':id/block')
  @ApiOperation({ summary: 'Заблокировать пользователя' })
  async block(@Param('id', ParseIntPipe) id: number) {
    return this.usersService.block(id);
  }

  @Patch(':id/unblock')
  @ApiOperation({ summary: 'Разблокировать пользователя' })
  async unblock(@Param('id', ParseIntPipe) id: number) {
    return this.usersService.unblock(id);
  }

  @Patch(':id/archive')
  @ApiOperation({ summary: 'Архивировать пользователя' })
  async archive(@Param('id', ParseIntPipe) id: number) {
    return this.usersService.archive(id);
  }

  @Patch(':id/restore')
  @ApiOperation({ summary: 'Восстановить пользователя' })
  async restore(@Param('id', ParseIntPipe) id: number) {
    return this.usersService.restore(id);
  }
}
