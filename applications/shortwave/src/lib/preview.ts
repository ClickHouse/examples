export type DestinationMetadata = {
  status: "ready" | "unavailable";
  title: string;
  description: string;
  siteName: string;
  image: string | null;
  imageAlt: string;
};
