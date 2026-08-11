import { access, mkdir, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";

import puppeteer from "puppeteer-core";

const require = createRequire(import.meta.url);
const screenPageHeight = 794;
const screenPageMargin = 45;
const minimumScreenPageWidth = 1122;
const maximumPdfPageDimension = 19_000;

async function existingPath(candidate) {
  if (!candidate) {
    return undefined;
  }
  try {
    await access(candidate, constants.X_OK);
    return candidate;
  } catch {
    return undefined;
  }
}

export async function findBrowserExecutable(explicitPath) {
  if (explicitPath) {
    const found = await existingPath(path.resolve(explicitPath));
    if (!found) {
      throw new Error(`Browser executable was not found: ${explicitPath}`);
    }
    return found;
  }

  const programFiles = [process.env.ProgramFiles, process.env["ProgramFiles(x86)"], process.env.LOCALAPPDATA]
    .filter(Boolean);
  const candidates = programFiles.flatMap((directory) => [
    path.join(directory, "Google", "Chrome", "Application", "chrome.exe"),
    path.join(directory, "Microsoft", "Edge", "Application", "msedge.exe"),
  ]);

  for (const candidate of candidates) {
    const found = await existingPath(candidate);
    if (found) {
      return found;
    }
  }

  throw new Error("Chrome or Microsoft Edge was not found. Install one or pass --browser <path>.");
}

export async function sizeScreenPages(page) {
  const measurements = await page.evaluate(() => {
    if (!document.body.classList.contains("pdf-layout--screen")) {
      return [];
    }
    return [...document.querySelectorAll("[data-screen-page]")].map((section) => {
      const content = section.querySelector("[data-screen-content]");
      if (!content) {
        throw new Error(`Missing screen content for ${section.dataset.screenPage}.`);
      }
      return {
        name: section.dataset.screenPage,
        contentWidth: Math.ceil(Math.max(content.scrollWidth, content.getBoundingClientRect().width)),
      };
    });
  });

  if (!measurements.length) {
    return [];
  }

  const pages = measurements.map(({ name, contentWidth }) => {
    const width = Math.max(minimumScreenPageWidth, contentWidth + screenPageMargin * 2);
    if (width > maximumPdfPageDimension) {
      throw new Error(`Screen layout for ${name} requires a page wider than Chromium's PDF limit. Use --layout print or reduce the longest code line.`);
    }
    return { name, width };
  });
  const rules = pages
    .map(({ name, width }) => `@page ${name} { size: ${width}px ${screenPageHeight}px; margin: ${screenPageMargin}px; }`)
    .join("\n");
  await page.addStyleTag({ content: rules });
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(resolve)));
  return pages;
}

export async function writePdfFromHtml(html, outputPath, browserPath) {
  const browser = await puppeteer.launch({
    executablePath: browserPath,
    headless: true,
    args: ["--disable-gpu"],
  });
  let stage = "create page";
  let failure;
  let result;

  try {
    const page = await browser.newPage();
    page.setDefaultTimeout(10_000);
    stage = "load rendered document";
    await page.setContent(html, { waitUntil: "load" });
    stage = "load Mermaid";
    await page.addScriptTag({ path: require.resolve("mermaid/dist/mermaid.min.js") });
    stage = "render Mermaid";
    await page.evaluate(async () => {
      window.mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: "default" });
      await window.mermaid.run({ querySelector: ".mermaid" });
    });
    result = { mermaidCount: await page.$$eval(".mermaid svg", (nodes) => nodes.length) };
    stage = "wait for fonts";
    await page.bringToFront();
    await page.evaluate(() => document.fonts.ready);
    stage = "size screen code pages";
    result.screenPages = await sizeScreenPages(page);
    stage = "generate PDF";

    const pdf = await page.pdf({
      preferCSSPageSize: true,
      printBackground: true,
      tagged: true,
    });
    stage = "write PDF";
    await mkdir(path.dirname(outputPath), { recursive: true });
    await writeFile(outputPath, pdf);
  } catch (error) {
    failure = new Error(`Failed to ${stage}: ${error.message}`, { cause: error });
    throw failure;
  } finally {
    try {
      await browser.close();
    } catch (closeError) {
      if (!failure) {
        throw closeError;
      }
    }
  }
  return result;
}
