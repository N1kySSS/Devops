package org.example;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

@Path("/work")
@Tag(name = "Work", description = "API для нагрузочного тестирования с rate limiting")
public class WorkResource {

  static List<String> syncList = Collections.synchronizedList(new ArrayList<>());
  int apiLimit;
  int timeout;

  public WorkResource(
      @ConfigProperty(name = "app.api.limit") int apiLimit,
      @ConfigProperty(name = "app.api.timeout") int timeout) {
    this.apiLimit = apiLimit;
    this.timeout = timeout;
  }

  @GET
  @Produces(MediaType.TEXT_PLAIN)
  @Operation(
      summary = "Выполнить работу",
      description =
          "Обрабатывает запрос с задержкой. При превышении лимита запросов возвращает 429")
  @APIResponse(responseCode = "429", description = "Превышен лимит запросов (Too Many Requests)")
  @APIResponse(responseCode = "200", description = "Успешное выполнение задачи ")
  public Response doWork() {
    if (syncList.size() > this.apiLimit) {
      return Response.status(429).entity("Too many requests - rate limit exceeded\n").build();
    }
    syncList.add("0");
    try {
      Thread.sleep(timeout);
    } catch (InterruptedException e) {
      throw new RuntimeException(e);
    }
    syncList.removeFirst();
    return Response.ok("OK\n").build();
  }

  @GET
  @Path("/status")
  @Produces(MediaType.TEXT_PLAIN)
  @Operation(
      summary = "Получить статус",
      description = "Возвращает текущее количество активных запросов")
  public Integer status() {
    return syncList.size();
  }
}
