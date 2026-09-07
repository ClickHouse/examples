if (!window.crypto) {
  window.crypto = {};
}

if (!window.crypto.randomUUID) {
  if (window.crypto.getRandomValues) {
    window.crypto.randomUUID = function () {
      const array = new Uint8Array(16);
      window.crypto.getRandomValues(array);

      array[6] = (array[6] & 0x0f) | 0x40;
      array[8] = (array[8] & 0x3f) | 0x80;

      const hex = Array.from(array)
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
      return [
        hex.slice(0, 8),
        hex.slice(8, 12),
        hex.slice(12, 16),
        hex.slice(16, 20),
        hex.slice(20, 32),
      ].join("-");
    };
  } else {
    window.crypto.randomUUID = function () {
      return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(
        /[xy]/g,
        function (c) {
          const r = (Math.random() * 16) | 0;
          const v = c === "x" ? r : (r & 0x3) | 0x8;
          return v.toString(16);
        }
      );
    };
  }
}
