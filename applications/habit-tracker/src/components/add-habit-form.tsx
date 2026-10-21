"use client";

import { Button, Container, TextField } from "@clickhouse/click-ui";
import { useActionState, useState } from "react";
import { createHabitAction } from "@/app/actions";

export function AddHabitForm() {
  const [name, setName] = useState("");
  const [state, formAction, pending] = useActionState(createHabitAction, {});

  return (
    <form action={formAction} onSubmit={() => setTimeout(() => setName(""))}>
      <Container gap="sm" alignItems="end">
        <TextField
          label="New habit"
          name="name"
          placeholder="Stretch for 10 minutes"
          value={name}
          onChange={setName}
          error={state.error}
          maxLength={60}
        />
        <Button htmlType="submit" label="Add habit" loading={pending} />
      </Container>
    </form>
  );
}
