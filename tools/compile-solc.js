const fs = require("fs");
const path = require("path");
const solc = require("solc");

const root = path.resolve(__dirname, "..");
const sourceDirs = ["src", "test", "script"];

function listSolidityFiles(dir) {
  const absDir = path.join(root, dir);
  if (!fs.existsSync(absDir)) return [];

  const entries = fs.readdirSync(absDir, { withFileTypes: true });
  return entries.flatMap((entry) => {
    const relPath = path.join(dir, entry.name);
    const absPath = path.join(root, relPath);

    if (entry.isDirectory()) return listSolidityFiles(relPath);
    if (entry.isFile() && entry.name.endsWith(".sol")) return [relPath];
    return [];
  });
}

const files = sourceDirs.flatMap(listSolidityFiles);
const sources = {};

for (const file of files) {
  sources[file] = { content: fs.readFileSync(path.join(root, file), "utf8") };
}

const input = {
  language: "Solidity",
  sources,
  settings: {
    optimizer: { enabled: true, runs: 200 },
    outputSelection: {
      "*": {
        "*": ["abi", "evm.bytecode.object"]
      }
    }
  }
};

function findImports(importPath) {
  if (importPath.startsWith("@uniswap/v4-core/")) {
    const mapped = importPath.replace("@uniswap/v4-core/", "lib/v4-core/");
    const absPath = path.join(root, mapped);
    if (fs.existsSync(absPath)) {
      return { contents: fs.readFileSync(absPath, "utf8") };
    }
  }

  if (importPath.startsWith("@uniswap/v4-periphery/")) {
    const mapped = importPath.replace("@uniswap/v4-periphery/", "lib/v4-periphery/");
    const absPath = path.join(root, mapped);
    if (fs.existsSync(absPath)) {
      return { contents: fs.readFileSync(absPath, "utf8") };
    }
  }

  if (importPath.startsWith("solmate/")) {
    const mapped = importPath.replace("solmate/", "lib/v4-core/lib/solmate/");
    const absPath = path.join(root, mapped);
    if (fs.existsSync(absPath)) {
      return { contents: fs.readFileSync(absPath, "utf8") };
    }
  }

  if (importPath.startsWith("forge-std/")) {
    const mapped = importPath.replace("forge-std/", "lib/v4-core/lib/forge-std/src/");
    const absPath = path.join(root, mapped);
    if (fs.existsSync(absPath)) {
      return { contents: fs.readFileSync(absPath, "utf8") };
    }
  }

  if (importPath.startsWith("@openzeppelin/")) {
    const mapped = importPath.replace("@openzeppelin/", "lib/v4-core/lib/openzeppelin-contracts/");
    const absPath = path.join(root, mapped);
    if (fs.existsSync(absPath)) {
      return { contents: fs.readFileSync(absPath, "utf8") };
    }
  }

  if (importPath.startsWith("openzeppelin-contracts/")) {
    const mapped = importPath.replace("openzeppelin-contracts/", "lib/v4-core/lib/openzeppelin-contracts/");
    const absPath = path.join(root, mapped);
    if (fs.existsSync(absPath)) {
      return { contents: fs.readFileSync(absPath, "utf8") };
    }
  }

  const candidates = [
    path.join(root, importPath),
    path.join(root, "src", importPath),
    path.join(root, "test", importPath),
    path.join(root, "script", importPath)
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return { contents: fs.readFileSync(candidate, "utf8") };
    }
  }

  return { error: `Import not found: ${importPath}` };
}

const output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImports }));
const errors = output.errors || [];

for (const error of errors) {
  const line = error.formattedMessage || error.message;
  if (error.severity === "error") {
    console.error(line);
  } else {
    console.warn(line);
  }
}

if (errors.some((error) => error.severity === "error")) {
  process.exit(1);
}

let contractCount = 0;
for (const contractsByFile of Object.values(output.contracts || {})) {
  contractCount += Object.keys(contractsByFile).length;
}

console.log(`Compiled ${contractCount} contracts from ${files.length} Solidity files.`);
