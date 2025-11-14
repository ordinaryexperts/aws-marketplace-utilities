# aws-marketplace-utilities

Helpful scripts for managing an AWS Marketplace product

## AMI Build Logging

The `ami-ec2-build` target automatically captures build output to timestamped log files in the `logs/` directory:

```bash
make ami-ec2-build TEMPLATE_VERSION=1.0.0
```

This will:
- Display all output to the terminal in real-time
- Save a complete log to `logs/ami-build-YYYYMMDD-HHMMSS.log`

### Recommended .gitignore

Add the following to your project's `.gitignore`:

```
# AMI build logs
logs/
```
