package com.amazonaws.demo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import jakarta.servlet.Filter;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Bean;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@SpringBootApplication
@RestController
public class Application {

    @GetMapping("/healthz")
    public String healthCheck() {
        return "healthy";
    }

    // Plain servlet filter — sets CORS headers without triggering Spring's
    // automatic Vary header injection, which produces multi-value headers that
    // violate the API Gateway streaming prelude schema.
    @Bean
    public Filter corsFilter() {
        return (req, res, chain) -> {
            HttpServletResponse r = (HttpServletResponse) res;
            r.setHeader("Access-Control-Allow-Origin", "*");
            r.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
            r.setHeader("Access-Control-Allow-Headers", "Content-Type, Accept");
            chain.doFilter(req, res);
        };
    }

    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}
