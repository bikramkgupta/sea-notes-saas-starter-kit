import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
  CreateBucketCommand,
  HeadBucketCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { StorageService } from './storage';
import { ServiceConfigStatus } from '../status/serviceConfigStatus';
import { serverConfig } from '../../settings';

/**
 * Service for interacting with DigitalOcean Spaces storage using the AWS S3 API.
 */
export class SpacesStorageService extends StorageService {
  private client: S3Client | null = null;
  private bucketName: string = '';
  private isConfigured: boolean = false;
  private configError: string = '';
  private lastConnectionError: string = '';
  private description: string = 'The following features are impacted: profile picture upload';

  // Service name for consistent display across all status responses
  private static readonly serviceName = 'Storage (DigitalOcean Spaces)';
  // Required config items with their corresponding env var names and descriptions
  private static requiredConfig = {
    SPACES_KEY_ID: { envVar: 'SPACES_KEY_ID', description: 'DigitalOcean Spaces Access Key' },
    SPACES_SECRET_KEY: {
      envVar: 'SPACES_SECRET_KEY',
      description: 'DigitalOcean Spaces Secret Key',
    },
    SPACES_BUCKET_NAME: { envVar: 'SPACES_BUCKET_NAME', description: 'Name of the Spaces bucket' },
    SPACES_REGION: { envVar: 'SPACES_REGION', description: 'DigitalOcean Spaces region' },
  };
  constructor() {
    super();
    this.initializeClient();
  }

  /**
   * Detects if the configured endpoint is a local MinIO/RustFS instance.
   * Local endpoints use http://, localhost, minio, or 127.0.0.1.
   */
  private isLocalMinIOEndpoint(): boolean {
    const endpoint = serverConfig.Spaces.SPACES_ENDPOINT || '';
    return (
      endpoint.startsWith('http://') ||
      endpoint.includes('localhost') ||
      endpoint.includes('minio') ||
      endpoint.includes('127.0.0.1')
    );
  }

  /**
   * Creates the bucket if it doesn't exist (local MinIO/RustFS only).
   * For production (DO Spaces), buckets must be created manually.
   */
  private async createBucket(): Promise<boolean> {
    if (!this.client) return false;

    try {
      await this.client.send(new CreateBucketCommand({ Bucket: this.bucketName }));
      console.log(`Bucket "${this.bucketName}" created successfully.`);
      return true;
    } catch (error: unknown) {
      // Bucket already exists - that's fine
      if (error && typeof error === 'object' && 'name' in error) {
        const errorName = error.name as string;
        if (errorName === 'BucketAlreadyOwnedByYou' || errorName === 'BucketAlreadyExists') {
          return true;
        }
      }
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.error('Failed to create bucket:', errorMessage);
      return false;
    }
  }

  /**
   * Initializes the S3 client based on the configuration.
   * Sets isConfigured flag and configError message if applicable.
   */
  private initializeClient(): void {
    try {
    const accessKeyId = serverConfig.Spaces.SPACES_KEY_ID;
    const secretAccessKey = serverConfig.Spaces.SPACES_SECRET_KEY;
    const bucketName = serverConfig.Spaces.SPACES_BUCKET_NAME;
    const region = serverConfig.Spaces.SPACES_REGION || 'us-east-1';
      
      // Use custom endpoint if provided, otherwise use default DO Spaces endpoint
      const endpoint = serverConfig.Spaces.SPACES_ENDPOINT 
        || `https://${region}.digitaloceanspaces.com`;
      
      // Auto-detect path-style for local MinIO, or use explicit config
      const forcePathStyle = serverConfig.Spaces.SPACES_FORCE_PATH_STYLE !== undefined
        ? serverConfig.Spaces.SPACES_FORCE_PATH_STYLE
        : this.isLocalMinIOEndpoint();

      // Check for missing configuration
      const missingConfig = Object.entries(SpacesStorageService.requiredConfig)
        .filter(([key]) => !serverConfig.Spaces[key as keyof typeof serverConfig.Spaces])
        .map(([, value]) => value.envVar);

      if (missingConfig.length > 0) {
        this.isConfigured = false;
        this.configError = 'Missing required configuration';
        return;
      }
      this.bucketName = bucketName!; // Safe to use ! here since we checked for missing config above
      this.client = new S3Client({
        forcePathStyle, // true for MinIO, false for DO Spaces
        endpoint,
        region,
        credentials: {
          accessKeyId: accessKeyId!, // Safe to use ! here since we checked for missing config above
          secretAccessKey: secretAccessKey!, // Safe to use ! here since we checked for missing config above
        },
      });
      this.isConfigured = true;
    } catch (error) {
      this.isConfigured = false;
      this.configError =
        error instanceof Error ? error.message : 'Unknown error initializing Spaces client';
    }
  }

  private getFilePath(userId: string, fileName: string): string {
    return `uploads/${userId}/${fileName}`;
  }
  async uploadFile(
    userId: string,
    fileName: string,
    file: File,
    { ACL = 'private' }: { ACL?: 'public-read' | 'private' }
  ): Promise<string> {
    if (!this.client) {
      throw new Error('Storage client not initialized. Check configuration.');
    }

    const fileBuffer = await file.arrayBuffer();

    const command = new PutObjectCommand({
      Bucket: this.bucketName,
      Key: this.getFilePath(userId, fileName),
      Body: Buffer.from(fileBuffer),
      ContentType: file.type,
      ACL,
    });

    await this.client.send(command);
    return fileName;
  }

  async getFileUrl(userId: string, fileName: string, expiresIn: number = 3600): Promise<string> {
    if (!this.client) {
      throw new Error('Storage client not initialized. Check configuration.');
    }

    const command = new GetObjectCommand({
      Bucket: this.bucketName,
      Key: this.getFilePath(userId, fileName),
    });

    return await getSignedUrl(this.client, command, { expiresIn });
  }

  async deleteFile(userId: string, fileName: string): Promise<void> {
    if (!this.client) {
      throw new Error('Storage client not initialized. Check configuration.');
    }

    const command = new DeleteObjectCommand({
      Bucket: this.bucketName,
      Key: this.getFilePath(userId, fileName),
    });
    await this.client.send(command);
  }

  /**
   * Checks if the Spaces service is properly configured and accessible.
   * Uses HeadBucketCommand to verify bucket access and connectivity.
   * For local MinIO/RustFS, auto-creates the bucket if it doesn't exist.
   *
   * @returns {Promise<boolean>} True if the connection is successful, false otherwise.
   */
  async checkConnection(): Promise<boolean> {
    if (!this.client) {
      this.lastConnectionError = 'Storage client not initialized';
      return false;
    }

    try {
      // Try to access the bucket
      await this.client.send(new HeadBucketCommand({ Bucket: this.bucketName }));
      return true;
    } catch (error: unknown) {
      const errorName = error && typeof error === 'object' && 'name' in error ? (error.name as string) : '';
      const bucketNotFound = errorName === 'NoSuchBucket' || errorName === 'NotFound';

      // Only auto-create for local MinIO/RustFS endpoints
      if (bucketNotFound && this.isLocalMinIOEndpoint()) {
        console.log(`Bucket not found. Creating "${this.bucketName}"...`);
        const created = await this.createBucket();
        if (created) {
          return true;  // Bucket created, connection successful
        }
      }

      // For production (DO Spaces), show error - bucket must be created manually
      const errorMsg = error instanceof Error ? error.message : String(error);
      console.error('Storage connection test failed:', {
        error: errorMsg,
      });

      // Store the last error details for use in checkConfiguration
      this.lastConnectionError = `Connection error: ${errorMsg}`;
      return false;
    }
  }

  /**
   * Checks if the storage service configuration is valid and tests connection when configuration is complete.
   */
  async checkConfiguration(): Promise<ServiceConfigStatus> {
    // Check for missing configuration
    const missingConfig = Object.entries(SpacesStorageService.requiredConfig)
      .filter(([key]) => !serverConfig.Spaces[key as keyof typeof serverConfig.Spaces])
      .map(([, value]) => value.envVar);

    if (missingConfig.length > 0) {
      return {
        name: SpacesStorageService.serviceName,
        configured: false,
        connected: undefined, // Don't test connection when configuration is missing
        configToReview: missingConfig,
        error: 'Configuration missing',
        description: this.description,
      };
    }

    // If configured, test the connection
    const isConnected = await this.checkConnection();
    if (!isConnected) {
      return {
        name: SpacesStorageService.serviceName,
        configured: true,
        connected: false,
        configToReview: Object.values(SpacesStorageService.requiredConfig).map(
          (config) => config.envVar
        ),
        error: this.lastConnectionError || 'Connection failed',
        description: this.description,
      };
    }

    return {
      name: SpacesStorageService.serviceName,
      configured: true,
      connected: true,
    };
  }
}
