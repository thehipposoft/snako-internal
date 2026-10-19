import type { MetadataRoute } from "next";

// Herramienta interna: no se indexa nada.
export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", disallow: "/" },
  };
}
