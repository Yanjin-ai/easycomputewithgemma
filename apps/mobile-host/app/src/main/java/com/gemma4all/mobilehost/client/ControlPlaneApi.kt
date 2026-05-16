package com.gemma4all.mobilehost.client

import com.gemma4all.mobilehost.models.Approval
import com.gemma4all.mobilehost.models.ApprovalResponse
import com.gemma4all.mobilehost.models.DeviceRegistrationRequest
import com.gemma4all.mobilehost.models.DeviceRegistrationResponse
import com.gemma4all.mobilehost.models.EventsResponse
import com.gemma4all.mobilehost.models.HeartbeatRequest
import com.gemma4all.mobilehost.models.HeartbeatResponse
import com.gemma4all.mobilehost.models.Task
import com.gemma4all.mobilehost.models.TaskDraft
import com.gemma4all.mobilehost.models.TasksResponse
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

interface ControlPlaneApi {
    @POST("v1/devices")
    suspend fun registerDevice(@Body request: DeviceRegistrationRequest): DeviceRegistrationResponse

    @POST("v1/tasks")
    suspend fun submitTask(@Body draft: TaskDraft): Task

    @GET("v1/tasks")
    suspend fun listTasks(
        @Query("limit") limit: Int = 50,
        @Query("before") before: String? = null
    ): TasksResponse

    @GET("v1/tasks/{taskId}")
    suspend fun getTask(@Path("taskId") taskId: String): Task

    @GET("v1/tasks/{taskId}/events")
    suspend fun getEvents(
        @Path("taskId") taskId: String,
        @Query("limit") limit: Int = 50,
        @Query("before") before: String? = null
    ): EventsResponse

    @GET("v1/approvals/{approvalId}")
    suspend fun getApproval(@Path("approvalId") approvalId: String): Approval

    @POST("v1/approvals/{approvalId}/respond")
    suspend fun respondApproval(
        @Path("approvalId") approvalId: String,
        @Body response: ApprovalResponse
    ): Approval

    @POST("v1/heartbeat")
    suspend fun postHeartbeat(@Body heartbeat: HeartbeatRequest): HeartbeatResponse
}
