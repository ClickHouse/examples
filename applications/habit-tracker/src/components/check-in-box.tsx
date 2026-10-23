"use client";

import { Checkbox } from "@clickhouse/click-ui";
import { useOptimistic, useTransition } from "react";
import { setCheckInAction } from "@/app/actions";

export function CheckInBox({
  habitId,
  day,
  done,
  label,
}: {
  habitId: number;
  day: string;
  done: boolean;
  label: string;
}) {
  const [optimisticDone, setOptimisticDone] = useOptimistic(done);
  const [pending, startTransition] = useTransition();

  return (
    <Checkbox
      aria-label={label}
      checked={optimisticDone}
      disabled={pending}
      onCheckedChange={(checked) =>
        startTransition(async () => {
          // Send the state the box should end up in, never "toggle": a repeated
          // request is then harmless.
          setOptimisticDone(checked === true);
          await setCheckInAction({ habitId, day, done: checked === true });
        })
      }
    />
  );
}
