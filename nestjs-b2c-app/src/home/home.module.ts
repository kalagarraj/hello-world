import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { HomeController } from './home.controller';

@Module({
  imports: [AuthModule],
  controllers: [HomeController],
})
export class HomeModule {}
