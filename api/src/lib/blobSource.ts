import { BlobServiceClient } from '@azure/storage-blob'

export async function readBlobText(
  connectionString: string,
  containerName: string,
  blobName: string,
): Promise<string> {
  const serviceClient = BlobServiceClient.fromConnectionString(connectionString)
  const containerClient = serviceClient.getContainerClient(containerName)
  const blobClient = containerClient.getBlobClient(blobName)
  const buffer = await blobClient.downloadToBuffer()
  return buffer.toString('utf-8')
}
