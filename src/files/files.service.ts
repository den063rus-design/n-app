import {
  Injectable,
  InternalServerErrorException,
  Logger,
} from '@nestjs/common';
import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { v4 as uuidv4 } from 'uuid';
import * as path from 'path';
import 'multer';

@Injectable()
export class FilesService {
  private readonly logger = new Logger(FilesService.name);
  private readonly s3Client: S3Client;
  private readonly bucket: string;
  private readonly endpoint: string;

  constructor() {
    this.endpoint = this.buildBaseUrl(
      process.env.MINIO_ENDPOINT || 'http://localhost',
      process.env.MINIO_PORT || '9000',
    );
    const accessKey = process.env.MINIO_ACCESS_KEY || 'minioadmin';
    const secretKey = process.env.MINIO_SECRET_KEY || 'minioadmin';
    this.bucket = process.env.MINIO_BUCKET || 'n-app-files';

    this.s3Client = new S3Client({
      endpoint: this.endpoint,
      region: 'us-east-1',
      credentials: {
        accessKeyId: accessKey,
        secretAccessKey: secretKey,
      },
      forcePathStyle: true,
    });
  }

  async uploadFile(file: Express.Multer.File): Promise<{ url: string; key: string }> {
    const ext = path.extname(file.originalname);
    const key = `${uuidv4()}${ext}`;

    try {
      await this.s3Client.send(
        new PutObjectCommand({
          Bucket: this.bucket,
          Key: key,
          Body: file.buffer,
          ContentType: file.mimetype,
          ContentLength: file.size,
        }),
      );

      const url = this.getFileUrl(key);

      this.logger.log(`File uploaded: ${key}`);

      return { url, key };
    } catch (error) {
      this.logger.error(`Failed to upload file: ${(error as Error).message}`);
      throw new InternalServerErrorException('Не удалось загрузить файл');
    }
  }

  async getFile(key: string): Promise<Buffer> {
    try {
      const response = await this.s3Client.send(
        new GetObjectCommand({
          Bucket: this.bucket,
          Key: key,
        }),
      );

      const chunks: Uint8Array[] = [];
      for await (const chunk of response.Body as AsyncIterable<Uint8Array>) {
        chunks.push(chunk);
      }

      return Buffer.concat(chunks);
    } catch (error) {
      this.logger.error(`Failed to get file: ${(error as Error).message}`);
      throw new InternalServerErrorException('Не удалось получить файл');
    }
  }

  async deleteFile(key: string): Promise<void> {
    try {
      await this.s3Client.send(
        new DeleteObjectCommand({
          Bucket: this.bucket,
          Key: key,
        }),
      );

      this.logger.log(`File deleted: ${key}`);
    } catch (error) {
      this.logger.error(`Failed to delete file: ${(error as Error).message}`);
      throw new InternalServerErrorException('Не удалось удалить файл');
    }
  }

  getFileUrl(key: string): string {
    return `${this.endpoint}/${this.bucket}/${key}`;
  }

  private buildBaseUrl(endpoint: string, port: string): string {
    const normalizedEndpoint = endpoint.replace(/\/+$/, '');

    try {
      const url = new URL(normalizedEndpoint);
      if (url.port) {
        return `${url.protocol}//${url.hostname}:${url.port}`;
      }

      url.port = port;
      return `${url.protocol}//${url.hostname}:${url.port}`;
    } catch {
      if (/:\d+$/.test(normalizedEndpoint)) {
        return normalizedEndpoint;
      }

      return `${normalizedEndpoint}:${port}`;
    }
  }
}
