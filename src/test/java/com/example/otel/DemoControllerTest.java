package com.example.otel;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.util.NestedServletException;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(DemoController.class)
class DemoControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void helloReturnsServiceMessage() throws Exception {
        mockMvc.perform(get("/api/hello"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message", is("hello opentelemetry")));
    }

    @Test
    void orderReturnsRequestedId() throws Exception {
        mockMvc.perform(get("/api/orders/1001"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id", is("1001")));
    }

    @Test
    void loadReportsRequestedSafeCount() throws Exception {
        mockMvc.perform(get("/api/load").param("count", "3"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.generated", is(3)));
    }

    @Test
    void errorEndpointReturnsServerError() throws Exception {
        NestedServletException exception = assertThrows(NestedServletException.class, () -> mockMvc.perform(get("/api/error")));
        assertTrue(exception.getCause() instanceof IllegalStateException);
    }
}
