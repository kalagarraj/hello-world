import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { HelloController } from './hello.controller';

@Module({
  imports: [AuthModule],
  controllers: [HelloController],
})
export class HelloModule {}
