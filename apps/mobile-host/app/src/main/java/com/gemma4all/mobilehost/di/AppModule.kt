package com.gemma4all.mobilehost.di

import com.gemma4all.mobilehost.client.ControlPlaneApi
import com.gemma4all.mobilehost.client.ControlPlaneClient
import com.gemma4all.mobilehost.client.RetrofitControlPlaneClient
import com.gemma4all.mobilehost.services.FunctionGemmaParserService
import com.gemma4all.mobilehost.services.HeartbeatService
import com.gemma4all.mobilehost.services.ParserRouterService
import com.gemma4all.mobilehost.services.PollingHeartbeatService
import dagger.Module
import dagger.Provides
import dagger.Binds
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import javax.inject.Named
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class AppBindingsModule {
    @Binds
    abstract fun bindParserRouterService(
        implementation: FunctionGemmaParserService
    ): ParserRouterService

    @Binds
    abstract fun bindHeartbeatService(
        implementation: PollingHeartbeatService
    ): HeartbeatService
}

@Module
@InstallIn(SingletonComponent::class)
object AppModule {
    @Provides
    @Singleton
    @Named("modelPath")
    fun provideModelPath(): String = "/sdcard/FunctionGemma-2B-it-int4.task"

    @Provides
    @Singleton
    fun provideOkHttpClient(): OkHttpClient {
        val logging = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        }
        return OkHttpClient.Builder()
            .addInterceptor(logging)
            .build()
    }

    @Provides
    @Singleton
    fun provideRetrofit(okHttpClient: OkHttpClient): Retrofit {
        return Retrofit.Builder()
            .baseUrl("https://control-plane.example.local/")
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    @Provides
    @Singleton
    fun provideControlPlaneClient(retrofit: Retrofit): ControlPlaneClient {
        return RetrofitControlPlaneClient(retrofit)
    }

    @Provides
    @Singleton
    fun provideControlPlaneApi(client: ControlPlaneClient): ControlPlaneApi {
        return client.api
    }
}
