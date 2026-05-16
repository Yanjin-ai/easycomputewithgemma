import Ajv from "ajv/dist/2020";
import { type AnySchema } from "ajv";
import addFormats from "ajv-formats";
import type { NextFunction, Request, Response } from "express";
import fs from "node:fs";
import path from "node:path";

const ajv = new Ajv({ allErrors: true, strict: false });
addFormats(ajv);

function findSchemasDir(): string {
  const candidates = [
    // When running as a pkg binary: schemas/ directory lives next to the executable
    path.join(path.dirname(process.execPath), "schemas"),
    path.resolve(process.cwd(), "packages/schemas"),
    path.resolve(process.cwd(), "../../packages/schemas"),
    path.resolve(__dirname, "../../../../packages/schemas"),
    path.resolve(__dirname, "../../../../../packages/schemas")
  ];

  const schemasDir = candidates.find((candidate) => fs.existsSync(candidate));
  if (!schemasDir) {
    throw new Error("Unable to locate packages/schemas");
  }
  return schemasDir;
}

function loadSchema(schemaFileName: string): AnySchema {
  const fullPath = path.join(findSchemasDir(), schemaFileName);
  return JSON.parse(fs.readFileSync(fullPath, "utf8")) as AnySchema;
}

const commonSchema = loadSchema("common.schema.json");
ajv.addSchema(commonSchema, "common.schema.json");

const schemaCache = new Map<string, ReturnType<typeof ajv.compile>>();

export function schemaValidator(schemaFileNameOrSchema: string | AnySchema) {
  const cacheKey =
    typeof schemaFileNameOrSchema === "string"
      ? schemaFileNameOrSchema
      : JSON.stringify(schemaFileNameOrSchema);

  let validate = schemaCache.get(cacheKey);
  if (!validate) {
    const schema =
      typeof schemaFileNameOrSchema === "string"
        ? loadSchema(schemaFileNameOrSchema)
        : schemaFileNameOrSchema;
    validate = ajv.compile(schema);
    schemaCache.set(cacheKey, validate);
  }

  return (req: Request, res: Response, next: NextFunction): void => {
    if (validate(req.body)) {
      next();
      return;
    }

    res.status(400).json({
      error: "schema_validation_failed",
      details: validate.errors ?? []
    });
  };
}
