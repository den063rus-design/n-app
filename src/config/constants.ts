export const jwtConstants = {
  secret: process.env.JWT_SECRET ?? 'super-secret-key-change-in-production',
  expiresIn: '7d' as const,
};