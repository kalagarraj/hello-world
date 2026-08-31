import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';

import { ApiDemoModule } from './api-demo/api-demo.module';
import { AuthModule } from './auth/auth.module';
import { HomeModule } from './home/home.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, cache: true }),
    AuthModule,
    HomeModule,
    ApiDemoModule,
  ],
})
export class AppModule {}
