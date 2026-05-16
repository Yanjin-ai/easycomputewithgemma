package com.gemma4all.mobilehost.client

import retrofit2.Retrofit

interface ControlPlaneClient {
    val api: ControlPlaneApi
}

class RetrofitControlPlaneClient(
    retrofit: Retrofit
) : ControlPlaneClient {
    override val api: ControlPlaneApi = retrofit.create(ControlPlaneApi::class.java)
}
