"use client";

import { ClickUIProvider, Container, Title } from "@clickhouse/click-ui";
import HomeView from "@/components/HomeView";

export default function Home() {
  return (
    <ClickUIProvider theme="dark">
      <Container
        gap="md"
        padding="md"
        maxWidth="100%"
        orientation="vertical"
        fillHeight
        style={{ height: "100vh", overflow: "hidden" }}
      >
        <Title type="h1" size="xl">
          StockHouse
        </Title>
        <HomeView />
      </Container>
    </ClickUIProvider>
  );
}
