import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { ApiDemoController } from './api-demo.controller';
import { ApiDemoService } from './api-demo.service';

@Module({
  imports: [AuthModule],
  controllers: [ApiDemoController],
  providers: [ApiDemoService],
})
export class ApiDemoModule {}
