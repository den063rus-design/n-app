import { PrismaClient, Role, UserStatus } from '@prisma/client';
import * as bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
  const existingAdmin = await prisma.user.findUnique({
    where: { login: 'admin' },
  });

  if (existingAdmin) {
    console.log('⚠️  Администратор уже существует, пропускаем seed.');
    return;
  }

  const passwordHash = await bcrypt.hash('admin123', 10);

  await prisma.user.create({
    data: {
      login: 'admin',
      passwordHash,
      role: Role.ADMIN,
      fio: 'Главный администратор',
      age: 30,
      status: UserStatus.ACTIVE,
    },
  });

  console.log('✅ Администратор успешно создан:');
  console.log('   Логин: admin');
  console.log('   Пароль: admin123');
  console.log('   Роль: ADMIN');
}

main()
  .catch((e) => {
    console.error('❌ Ошибка при выполнении seed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });