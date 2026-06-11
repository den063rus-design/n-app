export const jwtConstants = {
  secret: (() => {
    const secret = process.env.JWT_SECRET;
    if (!secret) {
      throw new Error('JWT_SECRET не задан в .env. Укажите JWT_SECRET в переменных окружения.');
    }
    return secret;
  })(),
  expiresIn: '7d' as const,
};
