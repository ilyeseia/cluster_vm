# API Reference

## Cluster Management API

### GET /cluster/status
Returns current cluster status.

**Response:**
```json
{
  "status": "healthy",
  "totalVMs": 3,
  "masterId": "vm-1234",
  "jobStats": {
    "completed": 45,
    "failed": 2
  }
}
