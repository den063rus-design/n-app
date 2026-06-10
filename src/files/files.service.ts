import {
  Injectable,
  InternalServerErrorException,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { DeleteObjectCommand, GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { promises as fs } from 'fs';
import * as path from 'path';
import { v4 as uuidv4 } from 'uuid';
import 'multer';

type StorageDriver = 'local' | 'minio';

@Injectable()
export class FilesService {
  private readonly logger = new Logger(FilesService.name);
  private readonly storageDriver: StorageDriver;
  private readonly uploadsDir: string;
  private readonly bucket: string;
  private readonly s3Client?: S3Client;

  constructor() {
    this.storageDriver = process.env.FILE_STORAGE_DRIVER === 'minio' ? 'minio' : 'local';
    this.uploadsDir = path.resolve(process.cwd(), 'uploads');
    this.bucket = process.env.MINIO_BUCKET || 'n-app-files';

    if (this.storageDriver === 'minio') {
      const endpoint = this.buildBaseUrl(
        process.env.MINIO_ENDPOINT || 'http://localhost',
        process.env.MINIO_PORT || '9000',
      );
      const accessKey = process.env.MINIO_ACCESS_KEY || 'minioadmin';
      const secretKey = process.env.MINIO_SECRET_KEY || 'minioadmin';

      this.s3Client = new S3Client({
        endpoint,
        region: 'us-east-1',
        credentials: {
          accessKeyId: accessKey,
          secretAccessKey: secretKey,
        },
        forcePathStyle: true,
      });
    }
  }

  async uploadFile(file: Express.Multer.File): Promise<{ url: string; key: string; mimeType: string; originalName: string; fileSize: number }> {
    if (!file) {
      throw new InternalServerErrorException('Файл не был передан');
    }

    const ext = path.extname(file.originalname);
    const key = `${uuidv4()}${ext}`;

    try {
      if (this.storageDriver === 'minio' && this.s3Client) {
        await this.s3Client.send(
          new PutObjectCommand({
            Bucket: this.bucket,
            Key: key,
            Body: file.buffer,
            ContentType: file.mimetype,
            ContentLength: file.size,
          }),
        );
      } else {
        await fs.mkdir(this.uploadsDir, { recursive: true });
        await fs.writeFile(path.join(this.uploadsDir, key), file.buffer);
      }

      const url = this.getFileUrl(key);
      this.logger.log(`File uploaded: ${key} (${this.storageDriver})`);
      return {
        url,
        key,
        mimeType: file.mimetype,
        originalName: file.originalname,
        fileSize: file.size,
      };
    } catch (error) {
      this.logger.error(`Failed to upload file: ${(error as Error).message}`);
      throw new InternalServerErrorException('Не удалось загрузить файл');
    }
  }

  async getFile(key: string): Promise<Buffer> {
    try {
      if (this.storageDriver === 'minio' && this.s3Client) {
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
      }

      return await fs.readFile(path.join(this.uploadsDir, key));
    } catch (error) {
      this.logger.error(`Failed to get file: ${(error as Error).message}`);
      throw new NotFoundException('Файл не найден');
    }
  }

  async deleteFile(key: string): Promise<void> {
    try {
      if (this.storageDriver === 'minio' && this.s3Client) {
        await this.s3Client.send(
          new DeleteObjectCommand({
            Bucket: this.bucket,
            Key: key,
          }),
        );
      } else {
        await fs.rm(path.join(this.uploadsDir, key), { force: true });
      }

      this.logger.log(`File deleted: ${key}`);
    } catch (error) {
      this.logger.error(`Failed to delete file: ${(error as Error).message}`);
      throw new InternalServerErrorException('Не удалось удалить файл');
    }
  }

  getFileUrl(key: string): string {
    return `/files/${key}`;
  }

  private buildBaseUrl(endpoint: string, port: string): string {
    const normalizedEndpoint = endpoint.replace(/\/+$/, '');

    try {
      const url = new URL(normalizedEndpoint);
      if (!url.port) {
        url.port = port;
      }
      return `${url.protocol}//${url.hostname}:${url.port}`;
    } catch {
      if (/:\d+$/.test(normalizedEndpoint)) {
        return normalizedEndpoint;
      }

      return `${normalizedEndpoint}:${port}`;
    }
  }
}
