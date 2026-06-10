import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import { UpdateCredentialsDto } from './dto/update-credentials.dto';
import { QueryUsersDto } from './dto/query-users.dto';
import { UsersService } from './users.service';

@ApiTags('Users')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('ADMIN')
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Post()
  @ApiOperation({ summary: 'Создать нового пользователя' })
  async create(@Body() dto: CreateUserDto) {
    return this.usersService.create(dto);
  }

  @Get()
  @ApiOperation({
    summary: 'Получить список пользователей (с поиском, сортировкой, фильтрацией)',
  })
  @ApiQuery({ name: 'search', required: false, description: 'Поиск по ФИО' })
  @ApiQuery({ name: 'sort', required: false, enum: ['name', 'age', 'created'] })
  @ApiQuery({ name: 'order', required: false, enum: ['asc', 'desc'] })
  @ApiQuery({ name: 'status', required: false, enum: ['ACTIVE', 'BLOCKED', 'ARCHIVED'] })
  async findAll(@Query() query: QueryUsersDto) {
    return this.usersService.findAll(query);
  }

  @Get('archive')
  @ApiOperation({ summary: 'Получить список архивных пользователей' })
  async findArchived() {
    return this.usersService.findArchived();
  }

  @Get(':id')
  @ApiOperation({ summary: 'Получить пользователя по ID' })
  async findOne(@Param('id', ParseIntPipe) id: number) {
    return this.usersService.findOne(id);
  }

  @Patch(':id')
  @ApiOperation({ summary: 'Обновить данные пользователя' })
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
  @ApiOperation({ summary: 'Восстановить пользователя из архива' })
  async restore(@Param('id', ParseIntPipe) id: number) {
    return this.usersService.restore(id);
  }

  @Patch(':id/credentials')
  @ApiOperation({ summary: 'Изменить логин и/или пароль пользователя' })
  async updateCredentials(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateCredentialsDto,
  ) {
    return this.usersService.updateCredentials(id, dto);
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Полностью удалить пользователя (только ARCHIVED)' })
  async remove(@Param('id', ParseIntPipe) id: number) {
    return this.usersService.remove(id);
  }
}
