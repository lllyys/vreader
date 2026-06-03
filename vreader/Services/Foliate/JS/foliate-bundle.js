var FoliateHost = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __esm = (fn, res) => function __init() {
    return fn && (res = (0, fn[__getOwnPropNames(fn)[0]])(fn = 0)), res;
  };
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };

  // epubcfi.js
  var findIndices, splitAt, concatArrays, isNumber, isCFI, escapeCFI, wrap, unwrap, lift, joinIndir, tokenizer, findTokens, parser, parserIndir, parse, partToString, toInnerString, toString, collapse, buildRange, isTextNode, isElementNode, getChildNodes, indexChildNodes, partsToNode, nodeToParts, fromRange, toRange, fromElements, toElement, fake;
  var init_epubcfi = __esm({
    "epubcfi.js"() {
      findIndices = (arr, f3) => arr.map((x3, i3, a3) => f3(x3, i3, a3) ? i3 : null).filter((x3) => x3 != null);
      splitAt = (arr, is) => [-1, ...is, arr.length].reduce(({ xs, a: a3 }, b3) => ({ xs: xs?.concat([arr.slice(a3 + 1, b3)]) ?? [], a: b3 }), {}).xs;
      concatArrays = (a3, b3) => a3.slice(0, -1).concat([a3[a3.length - 1].concat(b3[0])]).concat(b3.slice(1));
      isNumber = /\d/;
      isCFI = /^epubcfi\((.*)\)$/;
      escapeCFI = (str) => str.replace(/[\^[\](),;=]/g, "^$&");
      wrap = (x3) => isCFI.test(x3) ? x3 : `epubcfi(${x3})`;
      unwrap = (x3) => x3.match(isCFI)?.[1] ?? x3;
      lift = (f3) => (...xs) => `epubcfi(${f3(...xs.map((x3) => x3.match(isCFI)?.[1] ?? x3))})`;
      joinIndir = lift((...xs) => xs.join("!"));
      tokenizer = (str) => {
        const tokens = [];
        let state, escape, value = "";
        const push = (x3) => (tokens.push(x3), state = null, value = "");
        const cat = (x3) => (value += x3, escape = false);
        for (const char of Array.from(str.trim()).concat("")) {
          if (char === "^" && !escape) {
            escape = true;
            continue;
          }
          if (state === "!") push(["!"]);
          else if (state === ",") push([","]);
          else if (state === "/" || state === ":") {
            if (isNumber.test(char)) {
              cat(char);
              continue;
            } else push([state, parseInt(value)]);
          } else if (state === "~") {
            if (isNumber.test(char) || char === ".") {
              cat(char);
              continue;
            } else push(["~", parseFloat(value)]);
          } else if (state === "@") {
            if (char === ":") {
              push(["@", parseFloat(value)]);
              state = "@";
              continue;
            }
            if (isNumber.test(char) || char === ".") {
              cat(char);
              continue;
            } else push(["@", parseFloat(value)]);
          } else if (state === "[") {
            if (char === ";" && !escape) {
              push(["[", value]);
              state = ";";
            } else if (char === "," && !escape) {
              push(["[", value]);
              state = "[";
            } else if (char === "]" && !escape) push(["[", value]);
            else cat(char);
            continue;
          } else if (state?.startsWith(";")) {
            if (char === "=" && !escape) {
              state = `;${value}`;
              value = "";
            } else if (char === ";" && !escape) {
              push([state, value]);
              state = ";";
            } else if (char === "]" && !escape) push([state, value]);
            else cat(char);
            continue;
          }
          if (char === "/" || char === ":" || char === "~" || char === "@" || char === "[" || char === "!" || char === ",") state = char;
        }
        return tokens;
      };
      findTokens = (tokens, x3) => findIndices(tokens, ([t3]) => t3 === x3);
      parser = (tokens) => {
        const parts = [];
        let state;
        for (const [type, val] of tokens) {
          if (type === "/") parts.push({ index: val });
          else {
            const last = parts[parts.length - 1];
            if (type === ":") last.offset = val;
            else if (type === "~") last.temporal = val;
            else if (type === "@") last.spatial = (last.spatial ?? []).concat(val);
            else if (type === ";s") last.side = val;
            else if (type === "[") {
              if (state === "/" && val) last.id = val;
              else {
                last.text = (last.text ?? []).concat(val);
                continue;
              }
            }
          }
          state = type;
        }
        return parts;
      };
      parserIndir = (tokens) => splitAt(tokens, findTokens(tokens, "!")).map(parser);
      parse = (cfi) => {
        const tokens = tokenizer(unwrap(cfi));
        const commas = findTokens(tokens, ",");
        if (!commas.length) return parserIndir(tokens);
        const [parent, start, end] = splitAt(tokens, commas).map(parserIndir);
        return { parent, start, end };
      };
      partToString = ({ index, id, offset, temporal, spatial, text, side }) => {
        const param = side ? `;s=${side}` : "";
        return `/${index}` + (id ? `[${escapeCFI(id)}${param}]` : "") + (offset != null && index % 2 ? `:${offset}` : "") + (temporal ? `~${temporal}` : "") + (spatial ? `@${spatial.join(":")}` : "") + (text || !id && side ? "[" + (text?.map(escapeCFI)?.join(",") ?? "") + param + "]" : "");
      };
      toInnerString = (parsed) => parsed.parent ? [parsed.parent, parsed.start, parsed.end].map(toInnerString).join(",") : parsed.map((parts) => parts.map(partToString).join("")).join("!");
      toString = (parsed) => wrap(toInnerString(parsed));
      collapse = (x3, toEnd) => typeof x3 === "string" ? toString(collapse(parse(x3), toEnd)) : x3.parent ? concatArrays(x3.parent, x3[toEnd ? "end" : "start"]) : x3;
      buildRange = (from, to) => {
        if (typeof from === "string") from = parse(from);
        if (typeof to === "string") to = parse(to);
        from = collapse(from);
        to = collapse(to, true);
        const localFrom = from[from.length - 1], localTo = to[to.length - 1];
        const localParent = [], localStart = [], localEnd = [];
        let pushToParent = true;
        const len = Math.max(localFrom.length, localTo.length);
        for (let i3 = 0; i3 < len; i3++) {
          const a3 = localFrom[i3], b3 = localTo[i3];
          pushToParent &&= a3?.index === b3?.index && !a3?.offset && !b3?.offset;
          if (pushToParent) localParent.push(a3);
          else {
            if (a3) localStart.push(a3);
            if (b3) localEnd.push(b3);
          }
        }
        const parent = from.slice(0, -1).concat([localParent]);
        return toString({ parent, start: [localStart], end: [localEnd] });
      };
      isTextNode = ({ nodeType }) => nodeType === 3 || nodeType === 4;
      isElementNode = ({ nodeType }) => nodeType === 1;
      getChildNodes = (node, filter3) => {
        const nodes = Array.from(node.childNodes).filter((node2) => isTextNode(node2) || isElementNode(node2));
        return filter3 ? nodes.map((node2) => {
          const accept = filter3(node2);
          if (accept === NodeFilter.FILTER_REJECT) return null;
          else if (accept === NodeFilter.FILTER_SKIP) return getChildNodes(node2, filter3);
          else return node2;
        }).flat().filter((x3) => x3) : nodes;
      };
      indexChildNodes = (node, filter3) => {
        const nodes = getChildNodes(node, filter3).reduce((arr, node2) => {
          let last = arr[arr.length - 1];
          if (!last) arr.push(node2);
          else if (isTextNode(node2)) {
            if (Array.isArray(last)) last.push(node2);
            else if (isTextNode(last)) arr[arr.length - 1] = [last, node2];
            else arr.push(node2);
          } else {
            if (isElementNode(last)) arr.push(null, node2);
            else arr.push(node2);
          }
          return arr;
        }, []);
        if (isElementNode(nodes[0])) nodes.unshift("first");
        if (isElementNode(nodes[nodes.length - 1])) nodes.push("last");
        nodes.unshift("before");
        nodes.push("after");
        return nodes;
      };
      partsToNode = (node, parts, filter3) => {
        const { id } = parts[parts.length - 1];
        if (id) {
          const el = node.ownerDocument.getElementById(id);
          if (el) return { node: el, offset: 0 };
        }
        for (const { index } of parts) {
          const newNode = node ? indexChildNodes(node, filter3)[index] : null;
          if (newNode === "first") return { node: node.firstChild ?? node };
          if (newNode === "last") return { node: node.lastChild ?? node };
          if (newNode === "before") return { node, before: true };
          if (newNode === "after") return { node, after: true };
          node = newNode;
        }
        const { offset } = parts[parts.length - 1];
        if (!Array.isArray(node)) return { node, offset };
        let sum = 0;
        for (const n3 of node) {
          const { length } = n3.nodeValue;
          if (sum + length >= offset) return { node: n3, offset: offset - sum };
          sum += length;
        }
      };
      nodeToParts = (node, offset, filter3) => {
        let { id, parentNode } = node;
        while (filter3 && parentNode && parentNode !== node.ownerDocument.documentElement && filter3(parentNode) === NodeFilter.FILTER_SKIP)
          parentNode = parentNode.parentNode;
        const indexed = indexChildNodes(parentNode, filter3);
        const index = indexed.findIndex((x3) => Array.isArray(x3) ? x3.some((x4) => x4 === node) : x3 === node);
        const chunk = indexed[index];
        if (Array.isArray(chunk)) {
          let sum = 0;
          for (const x3 of chunk) {
            if (x3 === node) {
              sum += offset;
              break;
            } else sum += x3.nodeValue.length;
          }
          offset = sum;
        }
        const part = { id, index, offset };
        return (parentNode !== node.ownerDocument.documentElement ? nodeToParts(parentNode, null, filter3).concat(part) : [part]).filter((x3) => x3.index !== -1);
      };
      fromRange = (range, filter3) => {
        const { startContainer, startOffset, endContainer, endOffset } = range;
        const start = nodeToParts(startContainer, startOffset, filter3);
        if (range.collapsed) return toString([start]);
        const end = nodeToParts(endContainer, endOffset, filter3);
        return buildRange([start], [end]);
      };
      toRange = (doc, parts, filter3) => {
        const startParts = collapse(parts);
        const endParts = collapse(parts, true);
        const root = doc.documentElement;
        const start = partsToNode(root, startParts[0], filter3);
        const end = partsToNode(root, endParts[0], filter3);
        const range = doc.createRange();
        if (start.before) range.setStartBefore(start.node);
        else if (start.after) range.setStartAfter(start.node);
        else range.setStart(start.node, start.offset);
        if (end.before) range.setEndBefore(end.node);
        else if (end.after) range.setEndAfter(end.node);
        else range.setEnd(end.node, end.offset);
        return range;
      };
      fromElements = (elements) => {
        const results = [];
        const { parentNode } = elements[0];
        const parts = nodeToParts(parentNode);
        for (const [index, node] of indexChildNodes(parentNode).entries()) {
          const el = elements[results.length];
          if (node === el)
            results.push(toString([parts.concat({ id: el.id, index })]));
        }
        return results;
      };
      toElement = (doc, parts) => partsToNode(doc.documentElement, collapse(parts)).node;
      fake = {
        fromIndex: (index) => wrap(`/6/${(index + 1) * 2}`),
        toIndex: (parts) => parts?.at(-1).index / 2 - 1
      };
    }
  });

  // vendor/zip.js
  var zip_exports = {};
  __export(zip_exports, {
    BlobReader: () => Ge,
    BlobWriter: () => Je,
    TextWriter: () => Qe,
    ZipReader: () => Et,
    configure: () => w
  });
  function w(e3) {
    const { baseURI: t3, chunkSize: r3, maxWorkers: n3, terminateWorkerTimeout: s3, useCompressionStream: a3, useWebWorkers: i3, CompressionStream: o3, DecompressionStream: c2, CompressionStreamZlib: l3, DecompressionStreamZlib: u2, workerURI: d2, wasmURI: f3 } = e3;
    g("baseURI", t3), g("wasmURI", f3), g("workerURI", d2), g("chunkSize", r3), g("maxWorkers", n3), g("terminateWorkerTimeout", s3), g("useCompressionStream", a3), g("useWebWorkers", i3), g("CompressionStream", o3), g("DecompressionStream", c2), g("CompressionStreamZlib", l3), g("DecompressionStreamZlib", u2);
  }
  function g(e3, t3) {
    t3 !== c && (p[e3] = t3);
  }
  function E(e3) {
    return D ? crypto.getRandomValues(e3) : U.getRandomValues(e3);
  }
  function Y(e3, t3, r3, n3, s3, a3) {
    const { ctr: i3, hmac: o3, pending: c2 } = e3, l3 = t3.length - s3;
    let u2;
    for (c2.length && (t3 = te(c2, t3), r3 = (function(e4, t4) {
      if (t4 && t4 > e4.length) {
        const r4 = e4;
        (e4 = new Uint8Array(t4)).set(r4, 0);
      }
      return e4;
    })(r3, l3 - l3 % T)), u2 = 0; u2 <= l3 - T; u2 += T) {
      const e4 = se(Z, re(t3, u2, u2 + T));
      a3 && o3.update(e4);
      const s4 = i3.update(e4);
      a3 || o3.update(s4), r3.set(ne(Z, s4), u2 + n3);
    }
    return e3.pending = re(t3, u2), r3;
  }
  async function $(e3, t3, r3, n3) {
    e3.password = null;
    const s3 = await (async function(e4, t4, r4, n4, s4) {
      if (!G) return v.importKey(t4);
      try {
        return await V.importKey(e4, t4, r4, n4, s4);
      } catch {
        return G = false, v.importKey(t4);
      }
    })("raw", r3, R, false, M), a3 = await (async function(e4, t4, r4) {
      if (!J) return v.pbkdf2(t4, e4.salt, W.iterations, r4);
      try {
        return await V.deriveBits(e4, t4, r4);
      } catch {
        return J = false, v.pbkdf2(t4, e4.salt, W.iterations, r4);
      }
    })(Object.assign({ salt: n3 }, W), s3, 8 * (2 * I[t3] + 2)), i3 = new Uint8Array(a3), o3 = se(Z, re(i3, 0, I[t3])), c2 = se(Z, re(i3, I[t3], 2 * I[t3])), l3 = re(i3, 2 * I[t3]);
    return Object.assign(e3, { keys: { key: o3, authentication: c2, passwordVerification: l3 }, ctr: new H(new q(o3), Array.from(P)), hmac: new K(c2) }), l3;
  }
  function ee(e3, t3) {
    return t3 === c ? (function(e4) {
      if (typeof TextEncoder == u) {
        e4 = unescape(encodeURIComponent(e4));
        const t4 = new Uint8Array(e4.length);
        for (let r3 = 0; r3 < t4.length; r3++) t4[r3] = e4.charCodeAt(r3);
        return t4;
      }
      return new TextEncoder().encode(e4);
    })(e3) : t3;
  }
  function te(e3, t3) {
    let r3 = e3;
    return e3.length + t3.length && (r3 = new Uint8Array(e3.length + t3.length), r3.set(e3, 0), r3.set(t3, e3.length)), r3;
  }
  function re(e3, t3, r3) {
    return e3.subarray(t3, r3);
  }
  function ne(e3, t3) {
    return e3.fromBits(t3);
  }
  function se(e3, t3) {
    return e3.toBits(t3);
  }
  function oe(e3, t3) {
    const r3 = new Uint8Array(t3.length);
    for (let n3 = 0; n3 < t3.length; n3++) r3[n3] = de(e3) ^ t3[n3], ue(e3, r3[n3]);
    return r3;
  }
  function ce(e3, t3) {
    const r3 = new Uint8Array(t3.length);
    for (let n3 = 0; n3 < t3.length; n3++) r3[n3] = de(e3) ^ t3[n3], ue(e3, t3[n3]);
    return r3;
  }
  function le(e3, t3) {
    const r3 = [305419896, 591751049, 878082192];
    Object.assign(e3, { keys: r3, crcKey0: new y(r3[0]), crcKey2: new y(r3[2]) });
    for (let r4 = 0; r4 < t3.length; r4++) ue(e3, t3.charCodeAt(r4));
  }
  function ue(e3, t3) {
    let [r3, n3, s3] = e3.keys;
    e3.crcKey0.append([t3]), r3 = ~e3.crcKey0.get(), n3 = he(Math.imul(he(n3 + fe(r3)), 134775813) + 1), e3.crcKey2.append([n3 >>> 24]), s3 = ~e3.crcKey2.get(), e3.keys = [r3, n3, s3];
  }
  function de(e3) {
    const t3 = 2 | e3.keys[2];
    return fe(Math.imul(t3, 1 ^ t3) >>> 8);
  }
  function fe(e3) {
    return 255 & e3;
  }
  function he(e3) {
    return 4294967295 & e3;
  }
  function me(e3, t3, r3) {
    t3 = be(t3, new TransformStream({ flush: r3 })), Object.defineProperty(e3, "readable", { get: () => t3 });
  }
  function ye(e3, t3, r3, n3, s3, a3) {
    const i3 = t3 && n3 ? n3 : s3 || a3, o3 = r3.deflate64 ? "deflate64-raw" : "deflate-raw";
    try {
      e3 = be(e3, new i3(o3, r3));
    } catch (n4) {
      if (!t3) throw n4;
      if (s3) e3 = be(e3, new s3(o3, r3));
      else {
        if (!a3) throw n4;
        e3 = be(e3, new a3(o3, r3));
      }
    }
    return e3;
  }
  function be(e3, t3) {
    return e3.pipeThrough(t3);
  }
  async function Re(e3, ...t3) {
    try {
      await e3(...t3);
    } catch {
    }
  }
  function We(e3, t3) {
    return { run: () => (async function({ options: e4, readable: t4, writable: r3, onTaskFinished: n3 }, s3) {
      let a3;
      try {
        if (!e4.useCompressionStream) try {
          await void 0;
        } catch {
          e4.useCompressionStream = true;
        }
        a3 = new Ae(e4, s3), await t4.pipeThrough(a3).pipeTo(r3, { preventClose: true, preventAbort: true });
        const { signature: n4, inputSize: i3, outputSize: o3 } = a3;
        return { signature: n4, inputSize: i3, outputSize: o3 };
      } catch (e5) {
        throw a3 && (e5.outputSize = a3.outputSize), e5;
      } finally {
        n3();
      }
    })(e3, t3) };
  }
  function Me(e3, t3) {
    const { baseURI: r3, chunkSize: n3 } = t3;
    let { wasmURI: s3 } = t3;
    if (!e3.interface) {
      let a3;
      typeof s3 == d && (s3 = s3());
      try {
        a3 = je(e3.workerURI, r3, e3);
      } catch {
        return _e = false, We(e3, t3);
      }
      Object.assign(e3, { worker: a3, interface: { run: () => (async function(e4, t4) {
        let r4, n4;
        const s4 = new Promise((e5, t5) => {
          r4 = e5, n4 = t5;
        });
        Object.assign(e4, { reader: null, writer: null, resolveResult: r4, rejectResult: n4, result: s4 });
        const { readable: a4, options: i3 } = e4, { writable: o3, closed: c2 } = (function(e5) {
          const { writable: t5, readable: r5 } = new TransformStream(), n5 = r5.pipeTo(e5, { preventClose: true });
          return { writable: t5, closed: n5 };
        })(e4.writable), l3 = Ie({ type: Se, options: i3, config: t4, readable: a4, writable: o3 }, e4);
        l3 || Object.assign(e4, { reader: a4.getReader(), writer: o3.getWriter() });
        const u2 = await s4;
        l3 || await o3.getWriter().close();
        return await c2, u2;
      })(e3, { chunkSize: n3, wasmURI: s3, baseURI: r3 }) } });
    }
    return e3.interface;
  }
  function je(e3, t3, r3, n3, s3 = true) {
    let a3, i3, o3;
    if (Fe === c) {
      const l3 = typeof e3 == d;
      i3 = l3 ? e3(s3) : e3;
      const u2 = i3.startsWith("data:"), f3 = i3.startsWith("blob:");
      if (u2 || f3) {
        n3 === c && (n3 = false), n3 && (o3 = De);
        try {
          a3 = new Worker(i3, o3);
        } catch (s4) {
          if (f3) try {
            URL.revokeObjectURL(i3);
          } catch {
          }
          if (l3 && f3) return je(e3, t3, r3, n3, false);
          if (n3) throw s4;
          return je(e3, t3, r3, true, false);
        }
      } else {
        n3 === c && (n3 = true), n3 && (o3 = De);
        try {
          i3 = new URL(i3, t3);
        } catch {
        }
        try {
          a3 = new Worker(i3, o3);
        } catch (a4) {
          if (n3) throw a4;
          return je(e3, t3, r3, false, s3);
        }
      }
      Fe = i3, Oe = o3;
    } else a3 = new Worker(Fe, Oe);
    return a3.addEventListener("message", (e4) => (async function({ data: e5 }, t4) {
      const { type: r4, value: n4, messageId: s4, result: a4, error: i4 } = e5, { reader: o4, writer: c2, resolveResult: l3, rejectResult: u2, onTaskFinished: d2 } = t4;
      try {
        if (i4) {
          const { message: e6, stack: t5, code: r5, name: n5, outputSize: s5 } = i4, a5 = new Error(e6);
          Object.assign(a5, { stack: t5, code: r5, name: n5, outputSize: s5 }), f3(a5);
        } else {
          if (r4 == ke) {
            const { value: e6, done: r5 } = await o4.read();
            Ie({ type: ze, value: e6, done: r5, messageId: s4 }, t4);
          }
          r4 == ze && (await c2.ready, await c2.write(new Uint8Array(n4)), Ie({ type: "ack", messageId: s4 }, t4)), r4 == xe && f3(null, a4);
        }
      } catch (i5) {
        Ie({ type: xe, messageId: s4 }, t4), f3(i5);
      }
      function f3(e6, t5) {
        e6 ? u2(e6) : l3(t5), c2 && c2.releaseLock(), d2();
      }
    })(e4, r3)), a3;
  }
  function Ie(e3, { worker: t3, writer: r3, onTaskFinished: n3, transferStreams: s3 }) {
    try {
      const { value: r4, readable: n4, writable: a3 } = e3, i3 = [];
      if (r4 && (e3.value = r4, i3.push(e3.value.buffer)), s3 && Ee ? (n4 && i3.push(n4), a3 && i3.push(a3)) : e3.readable = e3.writable = null, i3.length) try {
        return t3.postMessage(e3, i3), true;
      } catch {
        Ee = false, e3.readable = e3.writable = null, t3.postMessage(e3);
      }
      else t3.postMessage(e3);
    } catch (e4) {
      throw r3 && r3.releaseLock(), n3(), e4;
    }
  }
  async function Ve(e3, t3) {
    const { options: r3, config: n3 } = t3, { transferStreams: s3, useWebWorkers: a3, useCompressionStream: i3, compressed: o3, signed: l3, encrypted: u2 } = r3, { workerURI: d2, maxWorkers: f3 } = n3;
    t3.transferStreams = s3 || s3 === c;
    const h3 = !(o3 || l3 || u2 || t3.transferStreams);
    return t3.useWebWorkers = !h3 && (a3 || a3 === c && n3.useWebWorkers), t3.workerURI = t3.useWebWorkers && d2 ? d2 : c, r3.useCompressionStream = i3 || i3 === c && n3.useCompressionStream, (await (async function() {
      const r4 = Be.find((e4) => !e4.busy);
      if (r4) return Ne(r4), new Te(r4, e3, t3, p3);
      if (Be.length < f3) {
        const r5 = { indexWorker: Le };
        return Le++, Be.push(r5), new Te(r5, e3, t3, p3);
      }
      return new Promise((r5) => Pe.push({ resolve: r5, stream: e3, workerOptions: t3 }));
    })()).run();
    function p3(e4) {
      if (Pe.length) {
        const [{ resolve: t4, stream: r4, workerOptions: n4 }] = Pe.splice(0, 1);
        t4(new Te(e4, r4, n4, p3));
      } else e4.worker ? (Ne(e4), (function(e5, t4) {
        const { config: r4 } = t4, { terminateWorkerTimeout: n4 } = r4;
        Number.isFinite(n4) && n4 >= 0 && (e5.terminated ? e5.terminated = false : e5.terminateTimeout = setTimeout(async () => {
          Be = Be.filter((t5) => t5 != e5);
          try {
            await e5.terminate();
          } catch {
          }
        }, n4));
      })(e4, t3)) : Be = Be.filter((t4) => t4 != e4);
    }
  }
  function Ne(e3) {
    const { terminateTimeout: t3 } = e3;
    t3 && (clearTimeout(t3), e3.terminateTimeout = null);
  }
  async function tt(e3, t3) {
    if (!e3.init || e3.initialized) return Promise.resolve();
    await e3.init(t3);
  }
  function rt(e3, t3, r3, n3) {
    return e3.readUint8Array(t3, r3, n3);
  }
  function at(e3, t3) {
    return t3 && "cp437" == t3.trim().toLowerCase() ? (function(e4) {
      if (st) {
        let t4 = "";
        for (let r3 = 0; r3 < e4.length; r3++) t4 += nt[e4[r3]];
        return t4;
      }
      return new TextDecoder().decode(e4);
    })(e3) : new TextDecoder(t3).decode(e3);
  }
  function Ct(e3, t3, r3) {
    const n3 = e3.rawBitFlag = Vt(t3, r3 + 2), s3 = !(1 & ~n3), a3 = Nt(t3, r3 + 6);
    Object.assign(e3, { encrypted: s3, version: Vt(t3, r3), bitFlag: { level: (6 & n3) >> 1, dataDescriptor: !(8 & ~n3), languageEncodingFlag: !(2048 & ~n3) }, rawLastModDate: a3, lastModDate: Bt(a3), filenameLength: Vt(t3, r3 + 22), extraFieldLength: Vt(t3, r3 + 24) });
  }
  function Rt(e3, t3, r3, n3, s3) {
    const { rawExtraField: a3 } = t3, i3 = t3.extraField = /* @__PURE__ */ new Map(), o3 = qt(new Uint8Array(a3));
    let c2 = 0;
    try {
      for (; c2 < a3.length; ) {
        const e4 = Vt(o3, c2), t4 = Vt(o3, c2 + 2);
        i3.set(e4, { type: e4, data: a3.slice(c2 + 4, c2 + 4 + t4) }), c2 += 4 + t4;
      }
    } catch {
    }
    const l3 = Vt(r3, n3 + 4);
    Object.assign(t3, { signature: Nt(r3, n3 + 10), compressedSize: Nt(r3, n3 + 14), uncompressedSize: Nt(r3, n3 + 18) });
    const u2 = i3.get(1);
    u2 && (!(function(e4, t4) {
      t4.zip64 = true;
      const r4 = qt(e4.data), n4 = Ft.filter(([e5, r5]) => t4[e5] == r5);
      for (let s4 = 0, a4 = 0; s4 < n4.length; s4++) {
        const [i4, o4] = n4[s4];
        if (t4[i4] == o4) {
          const n5 = Ot[o4];
          t4[i4] = e4[i4] = n5.getValue(r4, a4), a4 += n5.bytes;
        } else if (e4[i4]) throw new Error(xt);
      }
    })(u2, t3), t3.extraFieldZip64 = u2);
    const d2 = i3.get(28789);
    d2 && (Wt(d2, it, ot, t3, e3), t3.extraFieldUnicodePath = d2);
    const f3 = i3.get(25461);
    f3 && (Wt(f3, ct, lt, t3, e3), t3.extraFieldUnicodeComment = f3);
    const h3 = i3.get(39169);
    h3 ? (!(function(e4, t4, r4) {
      const n4 = qt(e4.data), s4 = Lt(n4, 4);
      Object.assign(e4, { vendorVersion: Lt(n4, 0), vendorId: Lt(n4, 2), strength: s4, originalCompressionMethod: r4, compressionMethod: Vt(n4, 5) }), t4.compressionMethod = e4.compressionMethod;
    })(h3, t3, l3), t3.extraFieldAES = h3) : t3.compressionMethod = l3;
    const p3 = i3.get(10);
    p3 && (!(function(e4, t4) {
      const r4 = qt(e4.data);
      let n4, s4 = 4;
      try {
        for (; s4 < e4.data.length && !n4; ) {
          const t5 = Vt(r4, s4), a4 = Vt(r4, s4 + 2);
          1 == t5 && (n4 = e4.data.slice(s4 + 4, s4 + 4 + a4)), s4 += 4 + a4;
        }
      } catch {
      }
      try {
        if (n4 && 24 == n4.length) {
          const r5 = qt(n4), s5 = r5.getBigUint64(0, true), a4 = r5.getBigUint64(8, true), i4 = r5.getBigUint64(16, true);
          Object.assign(e4, { rawLastModDate: s5, rawLastAccessDate: a4, rawCreationDate: i4 });
          const o4 = Pt(s5), c3 = Pt(a4), l4 = { lastModDate: o4, lastAccessDate: c3, creationDate: Pt(i4) };
          Object.assign(e4, l4), Object.assign(t4, l4);
        }
      } catch {
      }
    })(p3, t3), t3.extraFieldNTFS = p3);
    const w2 = i3.get(30805);
    if (w2) Mt(w2, t3, false), t3.extraFieldUnix = w2;
    else {
      const e4 = i3.get(30837);
      e4 && (Mt(e4, t3, true), t3.extraFieldInfoZip = e4);
    }
    const g3 = i3.get(21589);
    g3 && (!(function(e4, t4, r4) {
      const n4 = qt(e4.data), s4 = Lt(n4, 0), a4 = [], i4 = [];
      r4 ? (1 & ~s4 || (a4.push(pt), i4.push(wt)), 2 & ~s4 || (a4.push(gt), i4.push(mt)), 4 & ~s4 || (a4.push(yt), i4.push(bt))) : e4.data.length >= 5 && (a4.push(pt), i4.push(wt));
      let o4 = 1;
      a4.forEach((r5, s5) => {
        if (e4.data.length >= o4 + 4) {
          const a5 = Nt(n4, o4);
          t4[r5] = e4[r5] = new Date(1e3 * a5);
          const c3 = i4[s5];
          e4[c3] = a5;
        }
        o4 += 4;
      });
    })(g3, t3, s3), t3.extraFieldExtendedTimestamp = g3);
    const m3 = i3.get(6534);
    m3 && (t3.extraFieldUSDZ = m3);
  }
  function Wt(e3, t3, r3, n3, s3) {
    const a3 = qt(e3.data), i3 = new y();
    i3.append(s3[r3]);
    const o3 = qt(new Uint8Array(4));
    o3.setUint32(0, i3.get(), true);
    const c2 = Nt(a3, 1);
    Object.assign(e3, { version: Lt(a3, 0), [t3]: at(e3.data.subarray(5)), valid: !s3.bitFlag.languageEncodingFlag && c2 == Nt(o3, 0) }), e3.valid && (n3[t3] = e3[t3], n3[t3 + "UTF8"] = true);
  }
  function Mt(e3, t3, r3) {
    try {
      const n3 = qt(new Uint8Array(e3.data));
      let s3 = 0;
      const a3 = Lt(n3, s3++), i3 = Lt(n3, s3++), o3 = e3.data.subarray(s3, s3 + i3);
      s3 += i3;
      const l3 = jt(o3), u2 = Lt(n3, s3++), d2 = e3.data.subarray(s3, s3 + u2);
      s3 += u2;
      const f3 = jt(d2);
      let h3 = c;
      if (!r3 && s3 + 2 <= e3.data.length) {
        const t4 = e3.data;
        h3 = new DataView(t4.buffer, t4.byteOffset + s3, 2).getUint16(0, true);
      }
      Object.assign(e3, { version: a3, uid: l3, gid: f3, unixMode: h3 }), l3 !== c && (t3.uid = l3), f3 !== c && (t3.gid = f3), h3 !== c && (t3.unixMode = h3);
    } catch {
    }
  }
  function jt(e3) {
    const t3 = new Uint8Array(4);
    t3.set(e3, 0);
    return new DataView(t3.buffer, t3.byteOffset, 4).getUint32(0, true);
  }
  function It(e3, t3, r3) {
    return t3[r3] === c ? e3.options[r3] : t3[r3];
  }
  function Bt(e3) {
    const r3 = (4294901760 & e3) >> 16, n3 = e3 & t;
    try {
      return new Date(1980 + ((65024 & r3) >> 9), ((480 & r3) >> 5) - 1, 31 & r3, (63488 & n3) >> 11, (2016 & n3) >> 5, 2 * (31 & n3), 0);
    } catch {
    }
  }
  function Pt(e3) {
    return new Date(Number(e3 / BigInt(1e4) - BigInt(116444736e5)));
  }
  function Lt(e3, t3) {
    return e3.getUint8(t3);
  }
  function Vt(e3, t3) {
    return e3.getUint16(t3, true);
  }
  function Nt(e3, t3) {
    return e3.getUint32(t3, true);
  }
  function Zt(e3, t3) {
    return Number(e3.getBigUint64(t3, true));
  }
  function qt(e3) {
    return new DataView(e3.buffer);
  }
  var import_meta, e, t, r, n, s, a, i, o, c, l, u, d, f, h, p, m, y, b, S, k, z, x, U, A, v, D, _, F, O, T, C, R, W, M, j, I, B, P, L, V, N, Z, q, H, K, G, J, Q, X, ae, ie, pe, we, ge, Se, ke, ze, xe, Ue, Ae, ve, De, _e, Fe, Oe, Ee, Te, Ce, Be, Pe, Le, Ze, qe, He, Ke, Ge, Je, Qe, Xe, Ye, $e, et, nt, st, it, ot, ct, lt, ut, dt, ft, ht, pt, wt, gt, mt, yt, bt, St, kt, zt, xt, Ut, At, vt, Dt, _t, Ft, Ot, Et, Tt;
  var init_zip = __esm({
    "vendor/zip.js"() {
      import_meta = {};
      e = 4294967295;
      t = 65535;
      r = 134695760;
      n = r;
      s = 33639248;
      a = 101075792;
      i = 22;
      o = 16384;
      c = void 0;
      l = 1 / 0;
      u = "undefined";
      d = "function";
      f = 2;
      try {
        typeof navigator != u && navigator.hardwareConcurrency && (f = navigator.hardwareConcurrency);
      } catch {
      }
      h = { workerURI: "./core/web-worker-wasm.js", wasmURI: "./core/streams/zlib-wasm/zlib-streams.wasm", chunkSize: 65536, maxWorkers: f, terminateWorkerTimeout: 5e3, useWebWorkers: true, useCompressionStream: true, CompressionStream: typeof CompressionStream != u && CompressionStream, DecompressionStream: typeof DecompressionStream != u && DecompressionStream };
      p = Object.assign({}, h);
      m = [];
      for (let e3 = 0; e3 < 256; e3++) {
        let t3 = e3;
        for (let e4 = 0; e4 < 8; e4++) 1 & t3 ? t3 = t3 >>> 1 ^ 3988292384 : t3 >>>= 1;
        m[e3] = t3;
      }
      y = class {
        constructor(e3) {
          this.crc = e3 || -1;
        }
        append(e3) {
          let t3 = 0 | this.crc;
          for (let r3 = 0, n3 = 0 | e3.length; r3 < n3; r3++) t3 = t3 >>> 8 ^ m[255 & (t3 ^ e3[r3])];
          this.crc = t3;
        }
        get() {
          return ~this.crc;
        }
      };
      b = class extends TransformStream {
        constructor() {
          let e3;
          const t3 = new y();
          super({ transform(e4, r3) {
            t3.append(e4), r3.enqueue(e4);
          }, flush() {
            const r3 = new Uint8Array(4);
            new DataView(r3.buffer).setUint32(0, t3.get()), e3.value = r3;
          } }), e3 = this;
        }
      };
      S = { concat(e3, t3) {
        if (0 === e3.length || 0 === t3.length) return e3.concat(t3);
        const r3 = e3[e3.length - 1], n3 = S.getPartial(r3);
        return 32 === n3 ? e3.concat(t3) : S._shiftRight(t3, n3, 0 | r3, e3.slice(0, e3.length - 1));
      }, bitLength(e3) {
        const t3 = e3.length;
        if (0 === t3) return 0;
        const r3 = e3[t3 - 1];
        return 32 * (t3 - 1) + S.getPartial(r3);
      }, clamp(e3, t3) {
        if (32 * e3.length < t3) return e3;
        const r3 = (e3 = e3.slice(0, Math.ceil(t3 / 32))).length;
        return t3 &= 31, r3 > 0 && t3 && (e3[r3 - 1] = S.partial(t3, e3[r3 - 1] & 2147483648 >> t3 - 1, 1)), e3;
      }, partial: (e3, t3, r3) => 32 === e3 ? t3 : (r3 ? 0 | t3 : t3 << 32 - e3) + 1099511627776 * e3, getPartial: (e3) => Math.round(e3 / 1099511627776) || 32, _shiftRight(e3, t3, r3, n3) {
        for (void 0 === n3 && (n3 = []); t3 >= 32; t3 -= 32) n3.push(r3), r3 = 0;
        if (0 === t3) return n3.concat(e3);
        for (let s4 = 0; s4 < e3.length; s4++) n3.push(r3 | e3[s4] >>> t3), r3 = e3[s4] << 32 - t3;
        const s3 = e3.length ? e3[e3.length - 1] : 0, a3 = S.getPartial(s3);
        return n3.push(S.partial(t3 + a3 & 31, t3 + a3 > 32 ? r3 : n3.pop(), 1)), n3;
      } };
      k = { bytes: { fromBits(e3) {
        const t3 = S.bitLength(e3) / 8, r3 = new Uint8Array(t3);
        let n3;
        for (let s3 = 0; s3 < t3; s3++) 3 & s3 || (n3 = e3[s3 / 4]), r3[s3] = n3 >>> 24, n3 <<= 8;
        return r3;
      }, toBits(e3) {
        const t3 = [];
        let r3, n3 = 0;
        for (r3 = 0; r3 < e3.length; r3++) n3 = n3 << 8 | e3[r3], 3 & ~r3 || (t3.push(n3), n3 = 0);
        return 3 & r3 && t3.push(S.partial(8 * (3 & r3), n3)), t3;
      } } };
      z = { sha1: class {
        constructor(e3) {
          const t3 = this;
          t3.blockSize = 512, t3._init = [1732584193, 4023233417, 2562383102, 271733878, 3285377520], t3._key = [1518500249, 1859775393, 2400959708, 3395469782], e3 ? (t3._h = e3._h.slice(0), t3._buffer = e3._buffer.slice(0), t3._length = e3._length) : t3.reset();
        }
        reset() {
          const e3 = this;
          return e3._h = e3._init.slice(0), e3._buffer = [], e3._length = 0, e3;
        }
        update(e3) {
          const t3 = this;
          "string" == typeof e3 && (e3 = k.utf8String.toBits(e3));
          const r3 = t3._buffer = S.concat(t3._buffer, e3), n3 = t3._length, s3 = t3._length = n3 + S.bitLength(e3);
          if (s3 > 9007199254740991) throw new Error("Cannot hash more than 2^53 - 1 bits");
          const a3 = new Uint32Array(r3);
          let i3 = 0;
          for (let e4 = t3.blockSize + n3 - (t3.blockSize + n3 & t3.blockSize - 1); e4 <= s3; e4 += t3.blockSize) t3._block(a3.subarray(16 * i3, 16 * (i3 + 1))), i3 += 1;
          return r3.splice(0, 16 * i3), t3;
        }
        finalize() {
          const e3 = this;
          let t3 = e3._buffer;
          const r3 = e3._h;
          t3 = S.concat(t3, [S.partial(1, 1)]);
          for (let e4 = t3.length + 2; 15 & e4; e4++) t3.push(0);
          for (t3.push(Math.floor(e3._length / 4294967296)), t3.push(0 | e3._length); t3.length; ) e3._block(t3.splice(0, 16));
          return e3.reset(), r3;
        }
        _f(e3, t3, r3, n3) {
          return e3 <= 19 ? t3 & r3 | ~t3 & n3 : e3 <= 39 ? t3 ^ r3 ^ n3 : e3 <= 59 ? t3 & r3 | t3 & n3 | r3 & n3 : e3 <= 79 ? t3 ^ r3 ^ n3 : void 0;
        }
        _S(e3, t3) {
          return t3 << e3 | t3 >>> 32 - e3;
        }
        _block(e3) {
          const t3 = this, r3 = t3._h, n3 = Array(80);
          for (let t4 = 0; t4 < 16; t4++) n3[t4] = e3[t4];
          let s3 = r3[0], a3 = r3[1], i3 = r3[2], o3 = r3[3], c2 = r3[4];
          for (let e4 = 0; e4 <= 79; e4++) {
            e4 >= 16 && (n3[e4] = t3._S(1, n3[e4 - 3] ^ n3[e4 - 8] ^ n3[e4 - 14] ^ n3[e4 - 16]));
            const r4 = t3._S(5, s3) + t3._f(e4, a3, i3, o3) + c2 + n3[e4] + t3._key[Math.floor(e4 / 20)] | 0;
            c2 = o3, o3 = i3, i3 = t3._S(30, a3), a3 = s3, s3 = r4;
          }
          r3[0] = r3[0] + s3 | 0, r3[1] = r3[1] + a3 | 0, r3[2] = r3[2] + i3 | 0, r3[3] = r3[3] + o3 | 0, r3[4] = r3[4] + c2 | 0;
        }
      } };
      x = { aes: class {
        constructor(e3) {
          const t3 = this;
          t3._tables = [[[], [], [], [], []], [[], [], [], [], []]], t3._tables[0][0][0] || t3._precompute();
          const r3 = t3._tables[0][4], n3 = t3._tables[1], s3 = e3.length;
          let a3, i3, o3, c2 = 1;
          if (4 !== s3 && 6 !== s3 && 8 !== s3) throw new Error("invalid aes key size");
          for (t3._key = [i3 = e3.slice(0), o3 = []], a3 = s3; a3 < 4 * s3 + 28; a3++) {
            let e4 = i3[a3 - 1];
            (a3 % s3 === 0 || 8 === s3 && a3 % s3 === 4) && (e4 = r3[e4 >>> 24] << 24 ^ r3[e4 >> 16 & 255] << 16 ^ r3[e4 >> 8 & 255] << 8 ^ r3[255 & e4], a3 % s3 === 0 && (e4 = e4 << 8 ^ e4 >>> 24 ^ c2 << 24, c2 = c2 << 1 ^ 283 * (c2 >> 7))), i3[a3] = i3[a3 - s3] ^ e4;
          }
          for (let e4 = 0; a3; e4++, a3--) {
            const t4 = i3[3 & e4 ? a3 : a3 - 4];
            o3[e4] = a3 <= 4 || e4 < 4 ? t4 : n3[0][r3[t4 >>> 24]] ^ n3[1][r3[t4 >> 16 & 255]] ^ n3[2][r3[t4 >> 8 & 255]] ^ n3[3][r3[255 & t4]];
          }
        }
        encrypt(e3) {
          return this._crypt(e3, 0);
        }
        decrypt(e3) {
          return this._crypt(e3, 1);
        }
        _precompute() {
          const e3 = this._tables[0], t3 = this._tables[1], r3 = e3[4], n3 = t3[4], s3 = [], a3 = [];
          let i3, o3, c2, l3;
          for (let e4 = 0; e4 < 256; e4++) a3[(s3[e4] = e4 << 1 ^ 283 * (e4 >> 7)) ^ e4] = e4;
          for (let u2 = i3 = 0; !r3[u2]; u2 ^= o3 || 1, i3 = a3[i3] || 1) {
            let a4 = i3 ^ i3 << 1 ^ i3 << 2 ^ i3 << 3 ^ i3 << 4;
            a4 = a4 >> 8 ^ 255 & a4 ^ 99, r3[u2] = a4, n3[a4] = u2, l3 = s3[c2 = s3[o3 = s3[u2]]];
            let d2 = 16843009 * l3 ^ 65537 * c2 ^ 257 * o3 ^ 16843008 * u2, f3 = 257 * s3[a4] ^ 16843008 * a4;
            for (let r4 = 0; r4 < 4; r4++) e3[r4][u2] = f3 = f3 << 24 ^ f3 >>> 8, t3[r4][a4] = d2 = d2 << 24 ^ d2 >>> 8;
          }
          for (let r4 = 0; r4 < 5; r4++) e3[r4] = e3[r4].slice(0), t3[r4] = t3[r4].slice(0);
        }
        _crypt(e3, t3) {
          if (4 !== e3.length) throw new Error("invalid aes block size");
          const r3 = this._key[t3], n3 = r3.length / 4 - 2, s3 = [0, 0, 0, 0], a3 = this._tables[t3], i3 = a3[0], o3 = a3[1], c2 = a3[2], l3 = a3[3], u2 = a3[4];
          let d2, f3, h3, p3 = e3[0] ^ r3[0], w2 = e3[t3 ? 3 : 1] ^ r3[1], g3 = e3[2] ^ r3[2], m3 = e3[t3 ? 1 : 3] ^ r3[3], y3 = 4;
          for (let e4 = 0; e4 < n3; e4++) d2 = i3[p3 >>> 24] ^ o3[w2 >> 16 & 255] ^ c2[g3 >> 8 & 255] ^ l3[255 & m3] ^ r3[y3], f3 = i3[w2 >>> 24] ^ o3[g3 >> 16 & 255] ^ c2[m3 >> 8 & 255] ^ l3[255 & p3] ^ r3[y3 + 1], h3 = i3[g3 >>> 24] ^ o3[m3 >> 16 & 255] ^ c2[p3 >> 8 & 255] ^ l3[255 & w2] ^ r3[y3 + 2], m3 = i3[m3 >>> 24] ^ o3[p3 >> 16 & 255] ^ c2[w2 >> 8 & 255] ^ l3[255 & g3] ^ r3[y3 + 3], y3 += 4, p3 = d2, w2 = f3, g3 = h3;
          for (let e4 = 0; e4 < 4; e4++) s3[t3 ? 3 & -e4 : e4] = u2[p3 >>> 24] << 24 ^ u2[w2 >> 16 & 255] << 16 ^ u2[g3 >> 8 & 255] << 8 ^ u2[255 & m3] ^ r3[y3++], d2 = p3, p3 = w2, w2 = g3, g3 = m3, m3 = d2;
          return s3;
        }
      } };
      U = { getRandomValues(e3) {
        const t3 = new Uint32Array(e3.buffer), r3 = (e4) => {
          let t4 = 987654321;
          const r4 = 4294967295;
          return function() {
            t4 = 36969 * (65535 & t4) + (t4 >> 16) & r4;
            return (((t4 << 16) + (e4 = 18e3 * (65535 & e4) + (e4 >> 16) & r4) & r4) / 4294967296 + 0.5) * (Math.random() > 0.5 ? 1 : -1);
          };
        };
        for (let n3, s3 = 0; s3 < e3.length; s3 += 4) {
          const e4 = r3(4294967296 * (n3 || Math.random()));
          n3 = 987654071 * e4(), t3[s3 / 4] = 4294967296 * e4() | 0;
        }
        return e3;
      } };
      A = { ctrGladman: class {
        constructor(e3, t3) {
          this._prf = e3, this._initIv = t3, this._iv = t3;
        }
        reset() {
          this._iv = this._initIv;
        }
        update(e3) {
          return this.calculate(this._prf, e3, this._iv);
        }
        incWord(e3) {
          if (255 & ~(e3 >> 24)) e3 += 1 << 24;
          else {
            let t3 = e3 >> 16 & 255, r3 = e3 >> 8 & 255, n3 = 255 & e3;
            255 === t3 ? (t3 = 0, 255 === r3 ? (r3 = 0, 255 === n3 ? n3 = 0 : ++n3) : ++r3) : ++t3, e3 = 0, e3 += t3 << 16, e3 += r3 << 8, e3 += n3;
          }
          return e3;
        }
        incCounter(e3) {
          0 === (e3[0] = this.incWord(e3[0])) && (e3[1] = this.incWord(e3[1]));
        }
        calculate(e3, t3, r3) {
          let n3;
          if (!(n3 = t3.length)) return [];
          const s3 = S.bitLength(t3);
          for (let s4 = 0; s4 < n3; s4 += 4) {
            this.incCounter(r3);
            const n4 = e3.encrypt(r3);
            t3[s4] ^= n4[0], t3[s4 + 1] ^= n4[1], t3[s4 + 2] ^= n4[2], t3[s4 + 3] ^= n4[3];
          }
          return S.clamp(t3, s3);
        }
      } };
      v = { importKey: (e3) => new v.hmacSha1(k.bytes.toBits(e3)), pbkdf2(e3, t3, r3, n3) {
        if (r3 = r3 || 1e4, n3 < 0 || r3 < 0) throw new Error("invalid params to pbkdf2");
        const s3 = 1 + (n3 >> 5) << 2;
        let a3, i3, o3, c2, l3;
        const u2 = new ArrayBuffer(s3), d2 = new DataView(u2);
        let f3 = 0;
        const h3 = S;
        for (t3 = k.bytes.toBits(t3), l3 = 1; f3 < (s3 || 1); l3++) {
          for (a3 = i3 = e3.encrypt(h3.concat(t3, [l3])), o3 = 1; o3 < r3; o3++) for (i3 = e3.encrypt(i3), c2 = 0; c2 < i3.length; c2++) a3[c2] ^= i3[c2];
          for (o3 = 0; f3 < (s3 || 1) && o3 < a3.length; o3++) d2.setInt32(f3, a3[o3]), f3 += 4;
        }
        return u2.slice(0, n3 / 8);
      }, hmacSha1: class {
        constructor(e3) {
          const t3 = this, r3 = t3._hash = z.sha1, n3 = [[], []];
          t3._baseHash = [new r3(), new r3()];
          const s3 = t3._baseHash[0].blockSize / 32;
          e3.length > s3 && (e3 = new r3().update(e3).finalize());
          for (let t4 = 0; t4 < s3; t4++) n3[0][t4] = 909522486 ^ e3[t4], n3[1][t4] = 1549556828 ^ e3[t4];
          t3._baseHash[0].update(n3[0]), t3._baseHash[1].update(n3[1]), t3._resultHash = new r3(t3._baseHash[0]);
        }
        reset() {
          const e3 = this;
          e3._resultHash = new e3._hash(e3._baseHash[0]), e3._updated = false;
        }
        update(e3) {
          this._updated = true, this._resultHash.update(e3);
        }
        digest() {
          const e3 = this, t3 = e3._resultHash.finalize(), r3 = new e3._hash(e3._baseHash[1]).update(t3).finalize();
          return e3.reset(), r3;
        }
        encrypt(e3) {
          if (this._updated) throw new Error("encrypt on already updated hmac called!");
          return this.update(e3), this.digest(e3);
        }
      } };
      D = typeof crypto != u && typeof crypto.getRandomValues == d;
      _ = "Invalid password";
      F = "Invalid signature";
      O = "zipjs-abort-check-password";
      T = 16;
      C = { name: "PBKDF2" };
      R = Object.assign({ hash: { name: "HMAC" } }, C);
      W = Object.assign({ iterations: 1e3, hash: { name: "SHA-1" } }, C);
      M = ["deriveBits"];
      j = [8, 12, 16];
      I = [16, 24, 32];
      B = 10;
      P = [0, 0, 0, 0];
      L = typeof crypto != u;
      V = L && crypto.subtle;
      N = L && typeof V != u;
      Z = k.bytes;
      q = x.aes;
      H = A.ctrGladman;
      K = v.hmacSha1;
      G = L && N && typeof V.importKey == d;
      J = L && N && typeof V.deriveBits == d;
      Q = class extends TransformStream {
        constructor({ password: e3, rawPassword: t3, signed: r3, encryptionStrength: n3, checkPasswordOnly: s3 }) {
          super({ start() {
            Object.assign(this, { ready: new Promise((e4) => this.resolveReady = e4), password: ee(e3, t3), signed: r3, strength: n3 - 1, pending: new Uint8Array() });
          }, async transform(e4, t4) {
            const r4 = this, { password: n4, strength: a3, resolveReady: i3, ready: o3 } = r4;
            n4 ? (await (async function(e5, t5, r5, n5) {
              const s4 = await $(e5, t5, r5, re(n5, 0, j[t5])), a4 = re(n5, j[t5]);
              if (s4[0] != a4[0] || s4[1] != a4[1]) throw new Error(_);
            })(r4, a3, n4, re(e4, 0, j[a3] + 2)), e4 = re(e4, j[a3] + 2), s3 ? t4.error(new Error(O)) : i3()) : await o3;
            const c2 = new Uint8Array(e4.length - B - (e4.length - B) % T);
            t4.enqueue(Y(r4, e4, c2, 0, B, true));
          }, async flush(e4) {
            const { signed: t4, ctr: r4, hmac: n4, pending: s4, ready: a3 } = this;
            if (n4 && r4) {
              await a3;
              const i3 = re(s4, 0, s4.length - B), o3 = re(s4, s4.length - B);
              let c2 = new Uint8Array();
              if (i3.length) {
                const e5 = se(Z, i3);
                n4.update(e5);
                const t5 = r4.update(e5);
                c2 = ne(Z, t5);
              }
              if (t4) {
                const e5 = re(ne(Z, n4.digest()), 0, B);
                for (let t5 = 0; t5 < B; t5++) if (e5[t5] != o3[t5]) throw new Error(F);
              }
              e4.enqueue(c2);
            }
          } });
        }
      };
      X = class extends TransformStream {
        constructor({ password: e3, rawPassword: t3, encryptionStrength: r3 }) {
          let n3;
          super({ start() {
            Object.assign(this, { ready: new Promise((e4) => this.resolveReady = e4), password: ee(e3, t3), strength: r3 - 1, pending: new Uint8Array() });
          }, async transform(e4, t4) {
            const r4 = this, { password: n4, strength: s3, resolveReady: a3, ready: i3 } = r4;
            let o3 = new Uint8Array();
            n4 ? (o3 = await (async function(e5, t5, r5) {
              const n5 = E(new Uint8Array(j[t5])), s4 = await $(e5, t5, r5, n5);
              return te(n5, s4);
            })(r4, s3, n4), a3()) : await i3;
            const c2 = new Uint8Array(o3.length + e4.length - e4.length % T);
            c2.set(o3, 0), t4.enqueue(Y(r4, e4, c2, o3.length, 0));
          }, async flush(e4) {
            const { ctr: t4, hmac: r4, pending: s3, ready: a3 } = this;
            if (r4 && t4) {
              await a3;
              let i3 = new Uint8Array();
              if (s3.length) {
                const e5 = t4.update(se(Z, s3));
                r4.update(e5), i3 = ne(Z, e5);
              }
              n3.signature = ne(Z, r4.digest()).slice(0, B), e4.enqueue(te(i3, n3.signature));
            }
          } }), n3 = this;
        }
      };
      ae = class extends TransformStream {
        constructor({ password: e3, passwordVerification: t3, checkPasswordOnly: r3 }) {
          super({ start() {
            Object.assign(this, { password: e3, passwordVerification: t3 }), le(this, e3);
          }, transform(e4, t4) {
            const n3 = this;
            if (n3.password) {
              const t5 = oe(n3, e4.subarray(0, 12));
              if (n3.password = null, t5.at(-1) != n3.passwordVerification) throw new Error(_);
              e4 = e4.subarray(12);
            }
            r3 ? t4.error(new Error(O)) : t4.enqueue(oe(n3, e4));
          } });
        }
      };
      ie = class extends TransformStream {
        constructor({ password: e3, passwordVerification: t3 }) {
          super({ start() {
            Object.assign(this, { password: e3, passwordVerification: t3 }), le(this, e3);
          }, transform(e4, t4) {
            const r3 = this;
            let n3, s3;
            if (r3.password) {
              r3.password = null;
              const t5 = E(new Uint8Array(12));
              t5[11] = r3.passwordVerification, n3 = new Uint8Array(e4.length + t5.length), n3.set(ce(r3, t5), 0), s3 = 12;
            } else n3 = new Uint8Array(e4.length), s3 = 0;
            n3.set(ce(r3, e4), s3), t4.enqueue(n3);
          } });
        }
      };
      pe = "Invalid uncompressed size";
      we = class extends TransformStream {
        constructor(e3, { chunkSize: t3, CompressionStreamZlib: r3, CompressionStream: n3 }) {
          super({});
          const { compressed: s3, encrypted: a3, useCompressionStream: i3, zipCrypto: o3, signed: c2, level: l3 } = e3, u2 = this;
          let d2, f3, h3 = super.readable;
          a3 && !o3 || !c2 || (d2 = new b(), h3 = be(h3, d2)), s3 && (h3 = ye(h3, i3, { level: l3, chunkSize: t3 }, n3, r3, n3)), a3 && (o3 ? h3 = be(h3, new ie(e3)) : (f3 = new X(e3), h3 = be(h3, f3))), me(u2, h3, () => {
            let e4;
            a3 && !o3 && (e4 = f3.signature), a3 && !o3 || !c2 || (e4 = new DataView(d2.value.buffer).getUint32(0)), u2.signature = e4;
          });
        }
      };
      ge = class extends TransformStream {
        constructor(e3, { chunkSize: t3, DecompressionStreamZlib: r3, DecompressionStream: n3 }) {
          super({});
          const { zipCrypto: s3, encrypted: a3, signed: i3, signature: o3, compressed: c2, useCompressionStream: l3, deflate64: u2 } = e3;
          let d2, f3, h3 = super.readable;
          a3 && (s3 ? h3 = be(h3, new ae(e3)) : (f3 = new Q(e3), h3 = be(h3, f3))), c2 && (h3 = ye(h3, l3, { chunkSize: t3, deflate64: u2 }, n3, r3, n3)), a3 && !s3 || !i3 || (d2 = new b(), h3 = be(h3, d2)), me(this, h3, () => {
            if ((!a3 || s3) && i3) {
              const e4 = new DataView(d2.value.buffer);
              if (o3 != e4.getUint32(0, false)) throw new Error(F);
            }
          });
        }
      };
      Se = "start";
      ke = "pull";
      ze = "data";
      xe = "close";
      Ue = "inflate";
      Ae = class extends TransformStream {
        constructor(e3, t3) {
          super({});
          const r3 = this, { codecType: n3 } = e3;
          let s3;
          n3.startsWith("deflate") ? s3 = we : n3.startsWith(Ue) && (s3 = ge), r3.outputSize = 0;
          let a3 = 0;
          const i3 = new s3(e3, t3), o3 = super.readable, l3 = new TransformStream({ transform(e4, t4) {
            e4 && e4.length && (a3 += e4.length, t4.enqueue(e4));
          }, flush() {
            Object.assign(r3, { inputSize: a3 });
          } }), u2 = new TransformStream({ transform(t4, n4) {
            if (t4 && t4.length && (n4.enqueue(t4), r3.outputSize += t4.length, e3.outputSize !== c && r3.outputSize > e3.outputSize)) throw new Error(pe);
          }, flush() {
            const { signature: e4 } = i3;
            Object.assign(r3, { signature: e4, inputSize: a3 });
          } });
          Object.defineProperty(r3, "readable", { get: () => o3.pipeThrough(l3).pipeThrough(i3).pipeThrough(u2) });
        }
      };
      ve = class extends TransformStream {
        constructor(e3) {
          let t3;
          super({ transform: function r3(n3, s3) {
            if (t3) {
              const e4 = new Uint8Array(t3.length + n3.length);
              e4.set(t3), e4.set(n3, t3.length), n3 = e4, t3 = null;
            }
            n3.length > e3 ? (s3.enqueue(n3.slice(0, e3)), r3(n3.slice(e3), s3)) : t3 = n3;
          }, flush(e4) {
            t3 && t3.length && e4.enqueue(t3);
          } });
        }
      };
      De = { type: "module" };
      Ee = true;
      try {
        Ee = typeof structuredClone == d && structuredClone(new DOMException("", "AbortError")).code !== c;
      } catch {
      }
      Te = class {
        constructor(e3, { readable: t3, writable: r3 }, { options: n3, config: s3, streamOptions: a3, useWebWorkers: i3, transferStreams: o3, workerURI: l3 }, d2) {
          const { signal: f3 } = a3;
          return Object.assign(e3, { busy: true, readable: t3.pipeThrough(new ve(s3.chunkSize)).pipeThrough(new Ce(a3), { signal: f3 }), writable: r3, options: Object.assign({}, n3), workerURI: l3, transferStreams: o3, terminate: () => new Promise((t4) => {
            const { worker: r4, busy: n4 } = e3;
            r4 ? (n4 ? e3.resolveTerminated = t4 : (r4.terminate(), t4()), e3.interface = null) : t4();
          }), onTaskFinished() {
            const { resolveTerminated: t4 } = e3;
            t4 && (e3.resolveTerminated = null, e3.terminated = true, e3.worker.terminate(), t4()), e3.busy = false, d2(e3);
          } }), _e === c && (_e = typeof Worker != u), (i3 && _e ? Me : We)(e3, s3);
        }
      };
      Ce = class extends TransformStream {
        constructor({ onstart: e3, onprogress: t3, size: r3, onend: n3 }) {
          let s3 = 0;
          super({ async start() {
            e3 && await Re(e3, r3);
          }, async transform(e4, n4) {
            s3 += e4.length, t3 && await Re(t3, s3, r3), n4.enqueue(e4);
          }, async flush() {
            n3 && await Re(n3, s3);
          } });
        }
      };
      Be = [];
      Pe = [];
      Le = 0;
      Ze = 65536;
      qe = "writable";
      He = class {
        constructor() {
          this.size = 0;
        }
        init() {
          this.initialized = true;
        }
      };
      Ke = class extends He {
        get readable() {
          const e3 = this, { chunkSize: t3 = Ze } = e3, r3 = new ReadableStream({ start() {
            this.chunkOffset = 0;
          }, async pull(n3) {
            const { offset: s3 = 0, size: a3, diskNumberStart: i3 } = r3, { chunkOffset: o3 } = this, l3 = a3 === c ? t3 : Math.min(t3, a3 - o3), u2 = await rt(e3, s3 + o3, l3, i3);
            n3.enqueue(u2), o3 + t3 > a3 || a3 === c && !u2.length && l3 ? n3.close() : this.chunkOffset += t3;
          } });
          return r3;
        }
      };
      Ge = class extends Ke {
        constructor(e3) {
          super(), Object.assign(this, { blob: e3, size: e3.size });
        }
        async readUint8Array(e3, t3) {
          const r3 = this, n3 = e3 + t3, s3 = e3 || n3 < r3.size ? r3.blob.slice(e3, n3) : r3.blob;
          let a3 = await s3.arrayBuffer();
          return a3.byteLength > t3 && (a3 = a3.slice(e3, n3)), new Uint8Array(a3);
        }
      };
      Je = class extends He {
        constructor(e3) {
          super();
          const t3 = new TransformStream(), r3 = [];
          e3 && r3.push(["Content-Type", e3]), Object.defineProperty(this, qe, { get: () => t3.writable }), this.blob = new Response(t3.readable, { headers: r3 }).blob();
        }
        getData() {
          return this.blob;
        }
      };
      Qe = class extends Je {
        constructor(e3) {
          super(e3), Object.assign(this, { encoding: e3, utf8: !e3 || "utf-8" == e3.toLowerCase() });
        }
        async getData() {
          const { encoding: e3, utf8: t3 } = this, r3 = await super.getData();
          if (r3.text && t3) return r3.text();
          {
            const t4 = new FileReader();
            return new Promise((n3, s3) => {
              Object.assign(t4, { onload: ({ target: e4 }) => n3(e4.result), onerror: () => s3(t4.error) }), t4.readAsText(r3, e3);
            });
          }
        }
      };
      Xe = class extends Ke {
        constructor(e3) {
          super(), this.readers = e3;
        }
        async init() {
          const e3 = this, { readers: t3 } = e3;
          e3.lastDiskNumber = 0, e3.lastDiskOffset = 0, await Promise.all(t3.map(async (r3, n3) => {
            await r3.init(), n3 != t3.length - 1 && (e3.lastDiskOffset += r3.size), e3.size += r3.size;
          })), super.init();
        }
        async readUint8Array(e3, t3, r3 = 0) {
          const n3 = this, { readers: s3 } = this;
          let a3, i3 = r3;
          -1 == i3 && (i3 = s3.length - 1);
          let o3 = e3;
          for (; s3[i3] && o3 >= s3[i3].size; ) o3 -= s3[i3].size, i3++;
          const c2 = s3[i3];
          if (c2) {
            const s4 = c2.size;
            if (o3 + t3 <= s4) a3 = await rt(c2, o3, t3);
            else {
              const i4 = s4 - o3;
              a3 = new Uint8Array(t3);
              const l3 = await rt(c2, o3, i4);
              a3.set(l3, 0);
              const u2 = await n3.readUint8Array(e3 + i4, t3 - i4, r3);
              a3.set(u2, i4), l3.length + u2.length < t3 && (a3 = a3.subarray(0, l3.length + u2.length));
            }
          } else a3 = new Uint8Array();
          return n3.lastDiskNumber = Math.max(i3, n3.lastDiskNumber), a3;
        }
      };
      Ye = class extends He {
        constructor(e3, t3 = 4294967295) {
          super();
          const r3 = this;
          let n3, s3, a3;
          Object.assign(r3, { diskNumber: 0, diskOffset: 0, size: 0, maxSize: t3, availableSize: t3 });
          const i3 = new WritableStream({ async write(t4) {
            const { availableSize: i4 } = r3;
            if (a3) t4.length >= i4 ? (await o3(t4.subarray(0, i4)), await c2(), r3.diskOffset += n3.size, r3.diskNumber++, a3 = null, await this.write(t4.subarray(i4))) : await o3(t4);
            else {
              const { value: i5, done: o4 } = await e3.next();
              if (o4 && !i5) throw new Error("Writer iterator completed too soon");
              n3 = i5, n3.size = 0, n3.maxSize && (r3.maxSize = n3.maxSize), r3.availableSize = r3.maxSize, await tt(n3), s3 = i5.writable, a3 = s3.getWriter(), await this.write(t4);
            }
          }, async close() {
            await a3.ready, await c2();
          } });
          async function o3(e4) {
            const t4 = e4.length;
            t4 && (await a3.ready, await a3.write(e4), n3.size += t4, r3.size += t4, r3.availableSize -= t4);
          }
          async function c2() {
            await a3.close();
          }
          Object.defineProperty(r3, qe, { get: () => i3 });
        }
      };
      $e = class {
        constructor(e3) {
          return Array.isArray(e3) && (e3 = new Xe(e3)), e3 instanceof ReadableStream && (e3 = { readable: e3 }), e3;
        }
      };
      et = class {
        constructor(e3) {
          return e3.writable === c && typeof e3.next == d && (e3 = new Ye(e3)), e3 instanceof WritableStream && (e3 = { writable: e3 }), e3.size === c && (e3.size = 0), e3 instanceof Ye || Object.assign(e3, { diskNumber: 0, diskOffset: 0, availableSize: l, maxSize: l }), e3;
        }
      };
      nt = "\0\u263A\u263B\u2665\u2666\u2663\u2660\u2022\u25D8\u25CB\u25D9\u2642\u2640\u266A\u266B\u263C\u25BA\u25C4\u2195\u203C\xB6\xA7\u25AC\u21A8\u2191\u2193\u2192\u2190\u221F\u2194\u25B2\u25BC !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\u2302\xC7\xFC\xE9\xE2\xE4\xE0\xE5\xE7\xEA\xEB\xE8\xEF\xEE\xEC\xC4\xC5\xC9\xE6\xC6\xF4\xF6\xF2\xFB\xF9\xFF\xD6\xDC\xA2\xA3\xA5\u20A7\u0192\xE1\xED\xF3\xFA\xF1\xD1\xAA\xBA\xBF\u2310\xAC\xBD\xBC\xA1\xAB\xBB\u2591\u2592\u2593\u2502\u2524\u2561\u2562\u2556\u2555\u2563\u2551\u2557\u255D\u255C\u255B\u2510\u2514\u2534\u252C\u251C\u2500\u253C\u255E\u255F\u255A\u2554\u2569\u2566\u2560\u2550\u256C\u2567\u2568\u2564\u2565\u2559\u2558\u2552\u2553\u256B\u256A\u2518\u250C\u2588\u2584\u258C\u2590\u2580\u03B1\xDF\u0393\u03C0\u03A3\u03C3\xB5\u03C4\u03A6\u0398\u03A9\u03B4\u221E\u03C6\u03B5\u2229\u2261\xB1\u2265\u2264\u2320\u2321\xF7\u2248\xB0\u2219\xB7\u221A\u207F\xB2\u25A0 ".split("");
      st = 256 == nt.length;
      it = "filename";
      ot = "rawFilename";
      ct = "comment";
      lt = "rawComment";
      ut = "uncompressedSize";
      dt = "compressedSize";
      ft = "offset";
      ht = "diskNumberStart";
      pt = "lastModDate";
      wt = "rawLastModDate";
      gt = "lastAccessDate";
      mt = "rawLastAccessDate";
      yt = "creationDate";
      bt = "rawCreationDate";
      St = [it, ot, ut, dt, pt, wt, ct, lt, gt, yt, bt, ft, ht, "internalFileAttributes", "externalFileAttributes", "msdosAttributesRaw", "msdosAttributes", "msDosCompatible", "zip64", "encrypted", "version", "versionMadeBy", "zipCrypto", "directory", "executable", "compressionMethod", "signature", "extraField", "extraFieldUnix", "extraFieldInfoZip", "uid", "gid", "unixMode", "setuid", "setgid", "sticky", "bitFlag", "filenameUTF8", "commentUTF8", "rawExtraField", "extraFieldZip64", "extraFieldUnicodePath", "extraFieldUnicodeComment", "extraFieldAES", "extraFieldNTFS", "extraFieldExtendedTimestamp"];
      kt = class {
        constructor(e3) {
          St.forEach((t3) => this[t3] = e3[t3]);
        }
      };
      zt = "File format is not recognized";
      xt = "Zip64 extra field not found";
      Ut = "Compression method not supported";
      At = "Split zip file";
      vt = "Overlapping entry found";
      Dt = "utf-8";
      _t = "cp437";
      Ft = [[ut, e], [dt, e], [ft, e], [ht, t]];
      Ot = { [t]: { getValue: Nt, bytes: 4 }, [e]: { getValue: Zt, bytes: 8 } };
      Et = class {
        constructor(e3, t3 = {}) {
          Object.assign(this, { reader: new $e(e3), options: t3, config: p, readRanges: [] });
        }
        async *getEntriesGenerator(n3 = {}) {
          const l3 = this;
          let { reader: u2 } = l3;
          const { config: d2 } = l3;
          if (await tt(u2), u2.size !== c && u2.readUint8Array || (u2 = new Ge(await new Response(u2.readable).blob()), await tt(u2)), u2.size < i) throw new Error(zt);
          u2.chunkSize = (function(e3) {
            return Math.max(e3.chunkSize, 64);
          })(d2);
          const f3 = await (async function(e3, t3, r3, n4, s3) {
            const a3 = new Uint8Array(4);
            !(function(e4, t4, r4) {
              e4.setUint32(t4, r4, true);
            })(qt(a3), 0, t3);
            const i3 = n4 + s3;
            return await o3(n4) || await o3(Math.min(i3, r3));
            async function o3(t4) {
              const s4 = r3 - t4, i4 = await rt(e3, s4, t4);
              for (let e4 = i4.length - n4; e4 >= 0; e4--) if (i4[e4] == a3[0] && i4[e4 + 1] == a3[1] && i4[e4 + 2] == a3[2] && i4[e4 + 3] == a3[3]) return { offset: s4 + e4, buffer: i4.slice(e4, e4 + n4).buffer };
            }
          })(u2, 101010256, u2.size, i, 1048560);
          if (!f3) {
            throw Nt(qt(await rt(u2, 0, 4))) == r ? new Error(At) : new Error("End of central directory not found");
          }
          const h3 = qt(f3);
          let p3 = Nt(h3, 12), w2 = Nt(h3, 16);
          const g3 = f3.offset, m3 = Vt(h3, 20), y3 = g3 + i + m3;
          let b3 = Vt(h3, 4);
          const S2 = u2.lastDiskNumber || 0;
          let k3 = Vt(h3, 6), z3 = Vt(h3, 8), x3 = 0, U3 = 0;
          if (w2 == e || p3 == e || z3 == t || k3 == t) {
            const r3 = qt(await rt(u2, f3.offset - 20, 20));
            if (117853008 == Nt(r3, 0)) {
              w2 = Zt(r3, 8);
              let n4 = await rt(u2, w2, 56, -1), s3 = qt(n4);
              const i3 = f3.offset - 20 - 56;
              if (Nt(s3, 0) != a && w2 != i3) {
                const e3 = w2;
                w2 = i3, w2 > e3 && (x3 = w2 - e3), n4 = await rt(u2, w2, 56, -1), s3 = qt(n4);
              }
              if (Nt(s3, 0) != a) throw new Error("End of Zip64 central directory locator not found");
              b3 == t && (b3 = Nt(s3, 16)), k3 == t && (k3 = Nt(s3, 20)), z3 == t && (z3 = Zt(s3, 32)), p3 == e && (p3 = Zt(s3, 40)), w2 -= p3;
            }
          }
          if (w2 >= u2.size && (x3 = u2.size - w2 - p3 - i, w2 = u2.size - p3 - i), S2 != b3) throw new Error(At);
          if (w2 < 0) throw new Error(zt);
          let A3 = 0, v3 = await rt(u2, w2, p3, k3), D3 = qt(v3);
          if (p3) {
            const e3 = f3.offset - p3;
            if (Nt(D3, A3) != s && w2 != e3) {
              const t3 = w2;
              w2 = e3, w2 > t3 && (x3 += w2 - t3), v3 = await rt(u2, w2, p3, k3), D3 = qt(v3);
            }
          }
          const _2 = f3.offset - w2 - (u2.lastDiskOffset || 0);
          if (p3 != _2 && _2 >= 0 && (p3 = _2, v3 = await rt(u2, w2, p3, k3), D3 = qt(v3)), w2 < 0 || w2 >= u2.size) throw new Error(zt);
          const F2 = It(l3, n3, "filenameEncoding"), O2 = It(l3, n3, "commentEncoding");
          for (let e3 = 0; e3 < z3; e3++) {
            const r3 = new Tt(u2, d2, l3.options);
            if (Nt(D3, A3) != s) throw new Error("Central directory header not found");
            Ct(r3, D3, A3 + 6);
            const a3 = Boolean(r3.bitFlag.languageEncodingFlag), i3 = A3 + 46, f4 = i3 + r3.filenameLength, h4 = f4 + r3.extraFieldLength, p4 = Vt(D3, A3 + 4), w3 = !(p4 >> 8), g4 = p4 >> 8 == 3, m4 = v3.subarray(i3, f4), y4 = Vt(D3, A3 + 32), b4 = h4 + y4, S3 = v3.subarray(h4, b4), k4 = a3, _3 = a3, E4 = Nt(D3, A3 + 38), T4 = 255 & E4, C2 = { readOnly: Boolean(1 & T4), hidden: Boolean(2 & T4), system: Boolean(4 & T4), directory: Boolean(16 & T4), archive: Boolean(32 & T4) }, R2 = Nt(D3, A3 + 42) + x3, W2 = It(l3, n3, "decodeText") || at, M2 = k4 ? Dt : F2 || _t, j2 = _3 ? Dt : O2 || _t;
            let I2 = W2(m4, M2);
            I2 === c && (I2 = at(m4, M2));
            let B2 = W2(S3, j2);
            B2 === c && (B2 = at(S3, j2)), Object.assign(r3, { versionMadeBy: p4, msDosCompatible: w3, compressedSize: 0, uncompressedSize: 0, commentLength: y4, offset: R2, diskNumberStart: Vt(D3, A3 + 34), internalFileAttributes: Vt(D3, A3 + 36), externalFileAttributes: E4, msdosAttributesRaw: T4, msdosAttributes: C2, rawFilename: m4, filenameUTF8: k4, commentUTF8: _3, rawExtraField: v3.subarray(f4, h4), rawComment: S3, filename: I2, comment: B2 }), U3 = Math.max(R2, U3), Rt(r3, r3, D3, A3 + 6);
            const P2 = r3.externalFileAttributes >> 16 & t;
            r3.unixMode === c && 16877 & P2 && (r3.unixMode = P2);
            const L2 = Boolean(2048 & r3.unixMode), V2 = Boolean(1024 & r3.unixMode), N2 = Boolean(512 & r3.unixMode), Z2 = r3.unixMode !== c ? !!(73 & r3.unixMode) : g4 && !!(73 & P2), q2 = r3.unixMode !== c && (61440 & r3.unixMode) == o, H2 = (61440 & P2) == o;
            Object.assign(r3, { setuid: L2, setgid: V2, sticky: N2, unixExternalUpper: P2, internalFileAttribute: r3.internalFileAttributes, externalFileAttribute: r3.externalFileAttributes, executable: Z2, directory: q2 || H2 || w3 && C2.directory || I2.endsWith("/") && !r3.uncompressedSize, zipCrypto: r3.encrypted && !r3.extraFieldAES });
            const K2 = new kt(r3);
            K2.getData = (e4, t3) => r3.getData(e4, K2, l3.readRanges, t3), K2.arrayBuffer = async (e4) => {
              const t3 = new TransformStream(), [n4] = await Promise.all([new Response(t3.readable).arrayBuffer(), r3.getData(t3, K2, l3.readRanges, e4)]);
              return n4;
            }, A3 = b4;
            const { onprogress: G2 } = n3;
            if (G2) try {
              await G2(e3 + 1, z3, new kt(r3));
            } catch {
            }
            yield K2;
          }
          const E3 = It(l3, n3, "extractPrependedData"), T3 = It(l3, n3, "extractAppendedData");
          return E3 && (l3.prependedData = U3 > 0 ? await rt(u2, 0, U3) : new Uint8Array()), l3.comment = m3 ? await rt(u2, g3 + i, m3) : new Uint8Array(), T3 && (l3.appendedData = y3 < u2.size ? await rt(u2, y3, u2.size - y3) : new Uint8Array()), true;
        }
        async getEntries(e3 = {}) {
          const t3 = [];
          for await (const r3 of this.getEntriesGenerator(e3)) t3.push(r3);
          return t3;
        }
        async close() {
        }
      };
      Tt = class {
        constructor(e3, t3, r3) {
          Object.assign(this, { reader: e3, config: t3, options: r3 });
        }
        async getData(e3, t3, r3, s3 = {}) {
          const a3 = this, { reader: i3, offset: o3, diskNumberStart: l3, extraFieldAES: u2, extraFieldZip64: d2, compressionMethod: f3, config: h3, bitFlag: p3, signature: w2, rawLastModDate: g3, uncompressedSize: m3, compressedSize: y3 } = a3, { dataDescriptor: b3 } = p3, S2 = t3.localDirectory = {}, k3 = qt(await rt(i3, o3, 30, l3));
          let z3 = It(a3, s3, "password"), x3 = It(a3, s3, "rawPassword");
          const U3 = It(a3, s3, "passThrough");
          if (z3 = z3 && z3.length && z3, x3 = x3 && x3.length && x3, u2 && 99 != u2.originalCompressionMethod) throw new Error(Ut);
          if (0 != f3 && 8 != f3 && 9 != f3 && !U3) throw new Error(Ut);
          if (67324752 != Nt(k3, 0)) throw new Error("Local file header not found");
          Ct(S2, k3, 4);
          const { extraFieldLength: A3, filenameLength: v3, lastAccessDate: D3, creationDate: _2 } = S2;
          S2.rawExtraField = A3 ? await rt(i3, o3 + 30 + v3, A3, l3) : new Uint8Array(), Rt(a3, S2, k3, 4, true), Object.assign(t3, { lastAccessDate: D3, creationDate: _2 });
          const F2 = a3.encrypted && S2.encrypted && !U3, E3 = F2 && !u2;
          if (U3 || (t3.zipCrypto = E3), F2) {
            if (!E3 && u2.strength === c) throw new Error("Encryption method not supported");
            if (!z3 && !x3) throw new Error("File contains encrypted entry");
          }
          const T3 = o3 + 30 + v3 + A3, C2 = y3, R2 = i3.readable;
          Object.assign(R2, { diskNumberStart: l3, offset: T3, size: C2 });
          const W2 = It(a3, s3, "signal"), M2 = It(a3, s3, "checkPasswordOnly");
          let j2 = It(a3, s3, "checkOverlappingEntry");
          const I2 = It(a3, s3, "checkOverlappingEntryOnly");
          I2 && (j2 = true);
          const { onstart: B2, onprogress: P2, onend: L2 } = s3, V2 = 9 == f3;
          let N2 = It(a3, s3, "useCompressionStream");
          V2 && (N2 = false);
          const Z2 = { options: { codecType: Ue, password: z3, rawPassword: x3, zipCrypto: E3, encryptionStrength: u2 && u2.strength, signed: It(a3, s3, "checkSignature") && !U3, passwordVerification: E3 && (b3 ? g3 >>> 8 & 255 : w2 >>> 24 & 255), outputSize: U3 ? y3 : m3, signature: w2, compressed: 0 != f3 && !U3, encrypted: a3.encrypted && !U3, useWebWorkers: It(a3, s3, "useWebWorkers"), useCompressionStream: N2, transferStreams: It(a3, s3, "transferStreams"), deflate64: V2, checkPasswordOnly: M2 }, config: h3, streamOptions: { signal: W2, size: C2, onstart: B2, onprogress: P2, onend: L2 } };
          let q2;
          j2 && await (async function({ reader: e4, fileEntry: t4, offset: r4, diskNumberStart: s4, signature: a4, compressedSize: i4, uncompressedSize: o4, dataOffset: c2, dataDescriptor: l4, extraFieldZip64: u3, readRanges: d3 }) {
            let f4 = 0;
            if (s4) for (let t5 = 0; t5 < s4; t5++) {
              f4 += e4.readers[t5].size;
            }
            let h4 = 0;
            l4 && (h4 = u3 ? 20 : 12);
            if (h4) {
              const r5 = await rt(e4, c2 + i4, h4 + 4, s4);
              if (Nt(qt(r5), 0) == n) {
                const e5 = Nt(qt(r5), 4);
                let n3, s5;
                u3 ? (n3 = Zt(qt(r5), 8), s5 = Zt(qt(r5), 16)) : (n3 = Nt(qt(r5), 8), s5 = Nt(qt(r5), 12));
                (t4.encrypted && !t4.zipCrypto || e5 == a4) && n3 == i4 && s5 == o4 && (h4 += 4);
              }
            }
            const p4 = { start: f4 + r4, end: f4 + c2 + i4 + h4, fileEntry: t4 };
            for (const e5 of d3) if (e5.fileEntry != t4 && p4.start >= e5.start && p4.start < e5.end) {
              const t5 = new Error(vt);
              throw t5.overlappingEntry = e5.fileEntry, t5;
            }
            d3.push(p4);
          })({ reader: i3, fileEntry: t3, offset: o3, diskNumberStart: l3, signature: w2, compressedSize: y3, uncompressedSize: m3, dataOffset: T3, dataDescriptor: b3 || S2.bitFlag.dataDescriptor, extraFieldZip64: d2 || S2.extraFieldZip64, readRanges: r3 });
          try {
            if (!I2) {
              M2 && (e3 = new WritableStream()), e3 = new et(e3), await tt(e3, U3 ? y3 : m3), { writable: q2 } = e3;
              const { outputSize: t4 } = await Ve({ readable: R2, writable: q2 }, Z2);
              if (e3.size += t4, t4 != (U3 ? y3 : m3)) throw new Error(pe);
            }
          } catch (t4) {
            if (t4.outputSize !== c && (e3.size += t4.outputSize), !M2 || t4.message != O) throw t4;
          } finally {
            It(a3, s3, "preventClose") || !q2 || q2.locked || await q2.getWriter().close();
          }
          return M2 || I2 ? c : e3.getData ? e3.getData() : q2;
        }
      };
      try {
        w({ baseURI: import_meta.url });
      } catch {
      }
    }
  });

  // epub.js
  var epub_exports = {};
  __export(epub_exports, {
    EPUB: () => EPUB
  });
  var NS, MIME, PREFIX, RELATORS, ONIX5, camel, normalizeWhitespace, filterAttribute, getAttributes, getElementText, childGetter, resolveURL, isExternal, pathRelative, pathDirname, replaceSeries, regexEscape, tidy, getPrefixes, getPropertyURL, getMetadata, parseNav, parseNCX, parseClock, MediaOverlay, isUUID, getUUID, getIdentifier, deobfuscate, WebCryptoSHA1, deobfuscators, Encryption, Resources, Loader, getHTMLFragment, getPageSpread, getDisplayOptions, EPUB;
  var init_epub = __esm({
    "epub.js"() {
      init_epubcfi();
      NS = {
        CONTAINER: "urn:oasis:names:tc:opendocument:xmlns:container",
        XHTML: "http://www.w3.org/1999/xhtml",
        OPF: "http://www.idpf.org/2007/opf",
        EPUB: "http://www.idpf.org/2007/ops",
        DC: "http://purl.org/dc/elements/1.1/",
        DCTERMS: "http://purl.org/dc/terms/",
        ENC: "http://www.w3.org/2001/04/xmlenc#",
        NCX: "http://www.daisy.org/z3986/2005/ncx/",
        XLINK: "http://www.w3.org/1999/xlink",
        SMIL: "http://www.w3.org/ns/SMIL"
      };
      MIME = {
        XML: "application/xml",
        NCX: "application/x-dtbncx+xml",
        XHTML: "application/xhtml+xml",
        HTML: "text/html",
        CSS: "text/css",
        SVG: "image/svg+xml",
        JS: /\/(x-)?(javascript|ecmascript)/
      };
      PREFIX = {
        a11y: "http://www.idpf.org/epub/vocab/package/a11y/#",
        dcterms: "http://purl.org/dc/terms/",
        marc: "http://id.loc.gov/vocabulary/",
        media: "http://www.idpf.org/epub/vocab/overlays/#",
        onix: "http://www.editeur.org/ONIX/book/codelists/current.html#",
        rendition: "http://www.idpf.org/vocab/rendition/#",
        schema: "http://schema.org/",
        xsd: "http://www.w3.org/2001/XMLSchema#",
        msv: "http://www.idpf.org/epub/vocab/structure/magazine/#",
        prism: "http://www.prismstandard.org/specifications/3.0/PRISM_CV_Spec_3.0.htm#"
      };
      RELATORS = {
        art: "artist",
        aut: "author",
        clr: "colorist",
        edt: "editor",
        ill: "illustrator",
        nrt: "narrator",
        trl: "translator",
        pbl: "publisher"
      };
      ONIX5 = {
        "02": "isbn",
        "06": "doi",
        "15": "isbn",
        "26": "doi",
        "34": "issn"
      };
      camel = (x3) => x3.toLowerCase().replace(/[-:](.)/g, (_2, g3) => g3.toUpperCase());
      normalizeWhitespace = (str) => str ? str.replace(/[\t\n\f\r ]+/g, " ").replace(/^[\t\n\f\r ]+/, "").replace(/[\t\n\f\r ]+$/, "") : "";
      filterAttribute = (attr, value, isList) => isList ? (el) => el.getAttribute(attr)?.split(/\s/)?.includes(value) : typeof value === "function" ? (el) => value(el.getAttribute(attr)) : (el) => el.getAttribute(attr) === value;
      getAttributes = (...xs) => (el) => el ? Object.fromEntries(xs.map((x3) => [camel(x3), el.getAttribute(x3)])) : null;
      getElementText = (el) => normalizeWhitespace(el?.textContent);
      childGetter = (doc, ns) => {
        const useNS = doc.lookupNamespaceURI(null) === ns || doc.lookupPrefix(ns);
        const f3 = useNS ? (el, name) => (el2) => el2.namespaceURI === ns && el2.localName === name : (el, name) => (el2) => el2.localName === name;
        return {
          $: (el, name) => [...el.children].find(f3(el, name)),
          $$: (el, name) => [...el.children].filter(f3(el, name)),
          $$$: useNS ? (el, name) => [...el.getElementsByTagNameNS(ns, name)] : (el, name) => [...el.getElementsByTagName(name)]
        };
      };
      resolveURL = (url, relativeTo) => {
        try {
          if (relativeTo.includes(":")) return new URL(url, relativeTo);
          const root = "https://invalid.invalid/";
          const obj = new URL(url, root + relativeTo);
          obj.search = "";
          return decodeURI(obj.href.replace(root, ""));
        } catch (e3) {
          console.warn(e3);
          return url;
        }
      };
      isExternal = (uri) => /^(?!blob)\w+:/i.test(uri);
      pathRelative = (from, to) => {
        if (!from) return to;
        const as = from.replace(/\/$/, "").split("/");
        const bs = to.replace(/\/$/, "").split("/");
        const i3 = (as.length > bs.length ? as : bs).findIndex((_2, i4) => as[i4] !== bs[i4]);
        return i3 < 0 ? "" : Array(as.length - i3).fill("..").concat(bs.slice(i3)).join("/");
      };
      pathDirname = (str) => str.slice(0, str.lastIndexOf("/") + 1);
      replaceSeries = async (str, regex, f3) => {
        const matches = [];
        str.replace(regex, (...args) => (matches.push(args), null));
        const results = [];
        for (const args of matches) results.push(await f3(...args));
        return str.replace(regex, () => results.shift());
      };
      regexEscape = (str) => str.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&");
      tidy = (obj) => {
        for (const [key, val] of Object.entries(obj))
          if (val == null) delete obj[key];
          else if (Array.isArray(val)) {
            obj[key] = val.filter((x3) => x3).map((x3) => typeof x3 === "object" && !Array.isArray(x3) ? tidy(x3) : x3);
            if (!obj[key].length) delete obj[key];
            else if (obj[key].length === 1) obj[key] = obj[key][0];
          } else if (typeof val === "object") {
            obj[key] = tidy(val);
            if (!Object.keys(val).length) delete obj[key];
          }
        const keys = Object.keys(obj);
        if (keys.length === 1 && keys[0] === "name") return obj[keys[0]];
        return obj;
      };
      getPrefixes = (doc) => {
        const map = new Map(Object.entries(PREFIX));
        const value = doc.documentElement.getAttributeNS(NS.EPUB, "prefix") || doc.documentElement.getAttribute("prefix");
        if (value) for (const [, prefix, url] of value.matchAll(/(.+): +(.+)[ \t\r\n]*/g)) map.set(prefix, url);
        return map;
      };
      getPropertyURL = (value, prefixes) => {
        if (!value) return null;
        const [a3, b3] = value.split(":");
        const prefix = b3 ? a3 : null;
        const reference = b3 ? b3 : a3;
        const baseURL = prefixes.get(prefix);
        return baseURL ? baseURL + reference : null;
      };
      getMetadata = (opf) => {
        const { $: $2 } = childGetter(opf, NS.OPF);
        const $metadata = $2(opf.documentElement, "metadata");
        const els = Object.groupBy($metadata.children, (el) => el.namespaceURI === NS.DC ? "dc" : el.namespaceURI === NS.OPF && el.localName === "meta" ? el.hasAttribute("name") ? "legacyMeta" : "meta" : "");
        const baseLang = $metadata.getAttribute("xml:lang") ?? opf.documentElement.getAttribute("xml:lang") ?? "und";
        const prefixes = getPrefixes(opf);
        const parse2 = (el) => {
          const property = el.getAttribute("property");
          const scheme = el.getAttribute("scheme");
          return {
            property: getPropertyURL(property, prefixes) ?? property,
            scheme: getPropertyURL(scheme, prefixes) ?? scheme,
            lang: el.getAttribute("xml:lang"),
            value: getElementText(el),
            props: getProperties(el),
            // `opf:` attributes from EPUB 2 & EPUB 3.1 (removed in EPUB 3.2)
            attrs: Object.fromEntries(Array.from(el.attributes).filter((attr) => attr.namespaceURI === NS.OPF).map((attr) => [attr.localName, attr.value]))
          };
        };
        const refines = Map.groupBy(els.meta ?? [], (el) => el.getAttribute("refines"));
        const getProperties = (el) => {
          const els2 = refines.get(el ? "#" + el.getAttribute("id") : null);
          if (!els2) return null;
          return Object.groupBy(els2.map(parse2), (x3) => x3.property);
        };
        const dc = Object.fromEntries(Object.entries(Object.groupBy(els.dc, (el) => el.localName)).map(([name, els2]) => [name, els2.map(parse2)]));
        const properties = getProperties() ?? {};
        const legacyMeta = Object.fromEntries(els.legacyMeta?.map((el) => [el.getAttribute("name"), el.getAttribute("content")]) ?? []);
        const one = (x3) => x3?.[0]?.value;
        const prop = (x3, p3) => one(x3?.props?.[p3]);
        const makeLanguageMap = (x3) => {
          if (!x3) return null;
          const alts = x3.props?.["alternate-script"] ?? [];
          const altRep = x3.attrs["alt-rep"];
          if (!alts.length && (!x3.lang || x3.lang === baseLang) && !altRep) return x3.value;
          const map = { [x3.lang ?? baseLang]: x3.value };
          if (altRep) map[x3.attrs["alt-rep-lang"]] = altRep;
          for (const y3 of alts) map[y3.lang] ??= y3.value;
          return map;
        };
        const makeContributor = (x3) => x3 ? {
          name: makeLanguageMap(x3),
          sortAs: makeLanguageMap(x3.props?.["file-as"]?.[0]) ?? x3.attrs["file-as"],
          role: x3.props?.role?.filter((x4) => x4.scheme === PREFIX.marc + "relators")?.map((x4) => x4.value) ?? [x3.attrs.role],
          code: prop(x3, "term") ?? x3.attrs.term,
          scheme: prop(x3, "authority") ?? x3.attrs.authority
        } : null;
        const makeCollection = (x3) => ({
          name: makeLanguageMap(x3),
          // NOTE: webpub requires number but EPUB allows values like "2.2.1"
          position: one(x3.props?.["group-position"])
        });
        const makeAltIdentifier = (x3) => {
          const { value } = x3;
          if (/^urn:/i.test(value)) return value;
          if (/^doi:/i.test(value)) return `urn:${value}`;
          const type = x3.props?.["identifier-type"];
          if (!type) {
            const scheme = x3.attrs.scheme;
            if (!scheme) return value;
            if (/^(doi|isbn|uuid)$/i.test(scheme)) return `urn:${scheme}:${value}`;
            return { scheme, value };
          }
          if (type.scheme === PREFIX.onix + "codelist5") {
            const nid = ONIX5[type.value];
            if (nid) return `urn:${nid}:${value}`;
          }
          return value;
        };
        const belongsTo = Object.groupBy(
          properties["belongs-to-collection"] ?? [],
          (x3) => prop(x3, "collection-type") === "series" ? "series" : "collection"
        );
        const mainTitle = dc.title?.find((x3) => prop(x3, "title-type") === "main") ?? dc.title?.[0];
        const metadata = {
          identifier: getIdentifier(opf),
          title: makeLanguageMap(mainTitle),
          sortAs: makeLanguageMap(mainTitle?.props?.["file-as"]?.[0]) ?? mainTitle?.attrs?.["file-as"] ?? legacyMeta?.["calibre:title_sort"],
          subtitle: dc.title?.find((x3) => prop(x3, "title-type") === "subtitle")?.value,
          language: dc.language?.map((x3) => x3.value),
          description: one(dc.description),
          publisher: dc.publisher?.map(makeContributor),
          published: dc.date?.find((x3) => x3.attrs.event === "publication")?.value ?? one(dc.date),
          modified: one(properties[PREFIX.dcterms + "modified"]) ?? dc.date?.find((x3) => x3.attrs.event === "modification")?.value,
          subject: dc.subject?.map(makeContributor),
          belongsTo: {
            collection: belongsTo.collection?.map(makeCollection),
            series: belongsTo.series?.map(makeCollection) ?? legacyMeta?.["calibre:series"] ? {
              name: legacyMeta?.["calibre:series"],
              position: parseFloat(legacyMeta?.["calibre:series_index"])
            } : null
          },
          altIdentifier: dc.identifier?.map(makeAltIdentifier),
          source: dc.source?.map(makeAltIdentifier),
          // NOTE: not in webpub schema
          rights: one(dc.rights),
          // NOTE: not in webpub schema
          pageBreakSource: one(properties["pageBreakSource"])
          // NOTE: not in webpub schema
        };
        const remapContributor = (defaultKey) => (x3) => {
          const keys = new Set(x3.role?.map((role) => RELATORS[role] ?? defaultKey));
          return [keys.size ? keys : [defaultKey], x3];
        };
        for (const [keys, val] of [].concat(
          dc.creator?.map(makeContributor)?.map(remapContributor("author")) ?? [],
          dc.contributor?.map(makeContributor)?.map(remapContributor("contributor")) ?? []
        ))
          for (const key of keys)
            if (metadata[key]) metadata[key].push(val);
            else metadata[key] = [val];
        tidy(metadata);
        if (metadata.altIdentifier === metadata.identifier)
          delete metadata.altIdentifier;
        const rendition = {};
        const media = {};
        for (const [key, val] of Object.entries(properties)) {
          if (key.startsWith(PREFIX.rendition))
            rendition[camel(key.replace(PREFIX.rendition, ""))] = one(val);
          else if (key.startsWith(PREFIX.media))
            media[camel(key.replace(PREFIX.media, ""))] = one(val);
        }
        if (media.duration) media.duration = parseClock(media.duration);
        return { metadata, rendition, media };
      };
      parseNav = (doc, resolve = (f3) => f3) => {
        const { $: $2, $$, $$$ } = childGetter(doc, NS.XHTML);
        const resolveHref = (href) => href ? decodeURI(resolve(href)) : null;
        const parseLI = (getType) => ($li) => {
          const $a = $2($li, "a") ?? $2($li, "span");
          const $ol = $2($li, "ol");
          const href = resolveHref($a?.getAttribute("href"));
          const label = getElementText($a) || $a?.getAttribute("title");
          const result = { label, href, subitems: parseOL($ol) };
          if (getType) result.type = $a?.getAttributeNS(NS.EPUB, "type")?.split(/\s/);
          return result;
        };
        const parseOL = ($ol, getType) => $ol ? $$($ol, "li").map(parseLI(getType)) : null;
        const parseNav2 = ($nav, getType) => parseOL($2($nav, "ol"), getType);
        const $$nav = $$$(doc, "nav");
        let toc = null, pageList = null, landmarks = null, others = [];
        for (const $nav of $$nav) {
          const type = $nav.getAttributeNS(NS.EPUB, "type")?.split(/\s/) ?? [];
          if (type.includes("toc")) toc ??= parseNav2($nav);
          else if (type.includes("page-list")) pageList ??= parseNav2($nav);
          else if (type.includes("landmarks")) landmarks ??= parseNav2($nav, true);
          else others.push({
            label: getElementText($nav.firstElementChild),
            type,
            list: parseNav2($nav)
          });
        }
        return { toc, pageList, landmarks, others };
      };
      parseNCX = (doc, resolve = (f3) => f3) => {
        const { $: $2, $$ } = childGetter(doc, NS.NCX);
        const resolveHref = (href) => href ? decodeURI(resolve(href)) : null;
        const parseItem = (el) => {
          const $label = $2(el, "navLabel");
          const $content = $2(el, "content");
          const label = getElementText($label);
          const href = resolveHref($content.getAttribute("src"));
          if (el.localName === "navPoint") {
            const els = $$(el, "navPoint");
            return { label, href, subitems: els.length ? els.map(parseItem) : null };
          }
          return { label, href };
        };
        const parseList = (el, itemName) => $$(el, itemName).map(parseItem);
        const getSingle = (container, itemName) => {
          const $container = $2(doc.documentElement, container);
          return $container ? parseList($container, itemName) : null;
        };
        return {
          toc: getSingle("navMap", "navPoint"),
          pageList: getSingle("pageList", "pageTarget"),
          others: $$(doc.documentElement, "navList").map((el) => ({
            label: getElementText($2(el, "navLabel")),
            list: parseList(el, "navTarget")
          }))
        };
      };
      parseClock = (str) => {
        if (!str) return;
        const parts = str.split(":").map((x4) => parseFloat(x4));
        if (parts.length === 3) {
          const [h3, m3, s3] = parts;
          return h3 * 60 * 60 + m3 * 60 + s3;
        }
        if (parts.length === 2) {
          const [m3, s3] = parts;
          return m3 * 60 + s3;
        }
        const [x3, unit] = str.split(/(?=[^\d.])/);
        const n3 = parseFloat(x3);
        const f3 = unit === "h" ? 60 * 60 : unit === "min" ? 60 : unit === "ms" ? 1e-3 : 1;
        return n3 * f3;
      };
      MediaOverlay = class extends EventTarget {
        #entries;
        #lastMediaOverlayItem;
        #sectionIndex;
        #audioIndex;
        #itemIndex;
        #audio;
        #volume = 1;
        #rate = 1;
        #state;
        constructor(book, loadXML) {
          super();
          this.book = book;
          this.loadXML = loadXML;
        }
        async #loadSMIL(item) {
          if (this.#lastMediaOverlayItem === item) return;
          const doc = await this.loadXML(item.href);
          const resolve = (href) => href ? resolveURL(href, item.href) : null;
          const { $: $2, $$$ } = childGetter(doc, NS.SMIL);
          this.#audioIndex = -1;
          this.#itemIndex = -1;
          this.#entries = $$$(doc, "par").reduce((arr, $par) => {
            const text = resolve($2($par, "text")?.getAttribute("src"));
            const $audio = $2($par, "audio");
            if (!text || !$audio) return arr;
            const src = resolve($audio.getAttribute("src"));
            const begin = parseClock($audio.getAttribute("clipBegin"));
            const end = parseClock($audio.getAttribute("clipEnd"));
            const last = arr.at(-1);
            if (last?.src === src) last.items.push({ text, begin, end });
            else arr.push({ src, items: [{ text, begin, end }] });
            return arr;
          }, []);
          this.#lastMediaOverlayItem = item;
        }
        get #activeAudio() {
          return this.#entries[this.#audioIndex];
        }
        get #activeItem() {
          return this.#activeAudio?.items?.[this.#itemIndex];
        }
        #error(e3) {
          console.error(e3);
          this.dispatchEvent(new CustomEvent("error", { detail: e3 }));
        }
        #highlight() {
          this.dispatchEvent(new CustomEvent("highlight", { detail: this.#activeItem }));
        }
        #unhighlight() {
          this.dispatchEvent(new CustomEvent("unhighlight", { detail: this.#activeItem }));
        }
        async #play(audioIndex, itemIndex) {
          this.#stop();
          this.#audioIndex = audioIndex;
          this.#itemIndex = itemIndex;
          const src = this.#activeAudio?.src;
          if (!src || !this.#activeItem) return this.start(this.#sectionIndex + 1);
          const url = URL.createObjectURL(await this.book.loadBlob(src));
          const audio = new Audio(url);
          this.#audio = audio;
          audio.volume = this.#volume;
          audio.playbackRate = this.#rate;
          audio.addEventListener("timeupdate", () => {
            if (audio.paused) return;
            const t3 = audio.currentTime;
            const { items } = this.#activeAudio;
            if (t3 > this.#activeItem?.end) {
              this.#unhighlight();
              if (this.#itemIndex === items.length - 1) {
                this.#play(this.#audioIndex + 1, 0).catch((e3) => this.#error(e3));
                return;
              }
            }
            const oldIndex = this.#itemIndex;
            while (items[this.#itemIndex + 1]?.begin <= t3) this.#itemIndex++;
            if (this.#itemIndex !== oldIndex) this.#highlight();
          });
          audio.addEventListener("error", () => this.#error(new Error(`Failed to load ${src}`)));
          audio.addEventListener("playing", () => this.#highlight());
          audio.addEventListener("ended", () => {
            this.#unhighlight();
            URL.revokeObjectURL(url);
            this.#audio = null;
            this.#play(audioIndex + 1, 0).catch((e3) => this.#error(e3));
          });
          if (this.#state === "paused") {
            this.#highlight();
            audio.currentTime = this.#activeItem.begin ?? 0;
          } else audio.addEventListener("canplaythrough", () => {
            audio.currentTime = this.#activeItem.begin ?? 0;
            this.#state = "playing";
            audio.play().catch((e3) => this.#error(e3));
          }, { once: true });
        }
        async start(sectionIndex, filter3 = () => true) {
          this.#audio?.pause();
          const section = this.book.sections[sectionIndex];
          const href = section?.id;
          if (!href) return;
          const { mediaOverlay } = section;
          if (!mediaOverlay) return this.start(sectionIndex + 1);
          this.#sectionIndex = sectionIndex;
          await this.#loadSMIL(mediaOverlay);
          for (let i3 = 0; i3 < this.#entries.length; i3++) {
            const { items } = this.#entries[i3];
            for (let j2 = 0; j2 < items.length; j2++) {
              if (items[j2].text.split("#")[0] === href && filter3(items[j2], j2, items))
                return this.#play(i3, j2).catch((e3) => this.#error(e3));
            }
          }
        }
        pause() {
          this.#state = "paused";
          this.#audio?.pause();
        }
        resume() {
          this.#state = "playing";
          this.#audio?.play().catch((e3) => this.#error(e3));
        }
        #stop() {
          if (this.#audio) {
            this.#audio.pause();
            URL.revokeObjectURL(this.#audio.src);
            this.#audio = null;
            this.#unhighlight();
          }
        }
        stop() {
          this.#state = "stopped";
          this.#stop();
        }
        prev() {
          if (this.#itemIndex > 0) this.#play(this.#audioIndex, this.#itemIndex - 1);
          else if (this.#audioIndex > 0) this.#play(
            this.#audioIndex - 1,
            this.#entries[this.#audioIndex - 1].items.length - 1
          );
          else if (this.#sectionIndex > 0)
            this.start(this.#sectionIndex - 1, (_2, i3, items) => i3 === items.length - 1);
        }
        next() {
          this.#play(this.#audioIndex, this.#itemIndex + 1);
        }
        setVolume(volume) {
          this.#volume = volume;
          if (this.#audio) this.#audio.volume = volume;
        }
        setRate(rate) {
          this.#rate = rate;
          if (this.#audio) this.#audio.playbackRate = rate;
        }
      };
      isUUID = /([0-9a-f]{8})-([0-9a-f]{4})-([0-9a-f]{4})-([0-9a-f]{4})-([0-9a-f]{12})/;
      getUUID = (opf) => {
        for (const el of opf.getElementsByTagNameNS(NS.DC, "identifier")) {
          const [id] = getElementText(el).split(":").slice(-1);
          if (isUUID.test(id)) return id;
        }
        return "";
      };
      getIdentifier = (opf) => getElementText(
        opf.getElementById(opf.documentElement.getAttribute("unique-identifier")) ?? opf.getElementsByTagNameNS(NS.DC, "identifier")[0]
      );
      deobfuscate = async (key, length, blob) => {
        const array = new Uint8Array(await blob.slice(0, length).arrayBuffer());
        length = Math.min(length, array.length);
        for (var i3 = 0; i3 < length; i3++) array[i3] = array[i3] ^ key[i3 % key.length];
        return new Blob([array, blob.slice(length)], { type: blob.type });
      };
      WebCryptoSHA1 = async (str) => {
        const data = new TextEncoder().encode(str);
        const buffer = await globalThis.crypto.subtle.digest("SHA-1", data);
        return new Uint8Array(buffer);
      };
      deobfuscators = (sha1 = WebCryptoSHA1) => ({
        "http://www.idpf.org/2008/embedding": {
          key: (opf) => sha1(getIdentifier(opf).replaceAll(/[\u0020\u0009\u000d\u000a]/g, "")),
          decode: (key, blob) => deobfuscate(key, 1040, blob)
        },
        "http://ns.adobe.com/pdf/enc#RC": {
          key: (opf) => {
            const uuid = getUUID(opf).replaceAll("-", "");
            return Uint8Array.from({ length: 16 }, (_2, i3) => parseInt(uuid.slice(i3 * 2, i3 * 2 + 2), 16));
          },
          decode: (key, blob) => deobfuscate(key, 1024, blob)
        }
      });
      Encryption = class {
        #uris = /* @__PURE__ */ new Map();
        #decoders = /* @__PURE__ */ new Map();
        #algorithms;
        constructor(algorithms) {
          this.#algorithms = algorithms;
        }
        async init(encryption, opf) {
          if (!encryption) return;
          const data = Array.from(
            encryption.getElementsByTagNameNS(NS.ENC, "EncryptedData"),
            (el) => ({
              algorithm: el.getElementsByTagNameNS(NS.ENC, "EncryptionMethod")[0]?.getAttribute("Algorithm"),
              uri: el.getElementsByTagNameNS(NS.ENC, "CipherReference")[0]?.getAttribute("URI")
            })
          );
          for (const { algorithm, uri } of data) {
            if (!this.#decoders.has(algorithm)) {
              const algo = this.#algorithms[algorithm];
              if (!algo) {
                console.warn("Unknown encryption algorithm");
                continue;
              }
              const key = await algo.key(opf);
              this.#decoders.set(algorithm, (blob) => algo.decode(key, blob));
            }
            this.#uris.set(uri, algorithm);
          }
        }
        getDecoder(uri) {
          return this.#decoders.get(this.#uris.get(uri)) ?? ((x3) => x3);
        }
      };
      Resources = class {
        constructor({ opf, resolveHref }) {
          this.opf = opf;
          const { $: $2, $$, $$$ } = childGetter(opf, NS.OPF);
          const $manifest = $2(opf.documentElement, "manifest");
          const $spine = $2(opf.documentElement, "spine");
          const $$itemref = $$($spine, "itemref");
          this.manifest = $$($manifest, "item").map(getAttributes("href", "id", "media-type", "properties", "media-overlay")).map((item) => {
            item.href = resolveHref(item.href);
            item.properties = item.properties?.split(/\s/);
            return item;
          });
          this.manifestById = new Map(this.manifest.map((item) => [item.id, item]));
          this.spine = $$itemref.map(getAttributes("idref", "id", "linear", "properties")).map((item) => (item.properties = item.properties?.split(/\s/), item));
          this.pageProgressionDirection = $spine.getAttribute("page-progression-direction");
          this.navPath = this.getItemByProperty("nav")?.href;
          this.ncxPath = (this.getItemByID($spine.getAttribute("toc")) ?? this.manifest.find((item) => item.mediaType === MIME.NCX))?.href;
          const $guide = $2(opf.documentElement, "guide");
          if ($guide) this.guide = $$($guide, "reference").map(getAttributes("type", "title", "href")).map(({ type, title, href }) => ({
            label: title,
            type: type.split(/\s/),
            href: resolveHref(href)
          }));
          this.cover = this.getItemByProperty("cover-image") ?? this.getItemByID($$$(opf, "meta").find(filterAttribute("name", "cover"))?.getAttribute("content")) ?? this.getItemByHref(this.guide?.find((ref) => ref.type.includes("cover"))?.href);
          this.cfis = fromElements($$itemref);
        }
        getItemByID(id) {
          return this.manifestById.get(id);
        }
        getItemByHref(href) {
          return this.manifest.find((item) => item.href === href);
        }
        getItemByProperty(prop) {
          return this.manifest.find((item) => item.properties?.includes(prop));
        }
        resolveCFI(cfi) {
          const parts = parse(cfi);
          const top = (parts.parent ?? parts).shift();
          let $itemref = toElement(this.opf, top);
          if ($itemref && $itemref.nodeName !== "idref") {
            top.at(-1).id = null;
            $itemref = toElement(this.opf, top);
          }
          const idref = $itemref?.getAttribute("idref");
          const index = this.spine.findIndex((item) => item.idref === idref);
          const anchor = (doc) => toRange(doc, parts);
          return { index, anchor };
        }
      };
      Loader = class {
        #cache = /* @__PURE__ */ new Map();
        #children = /* @__PURE__ */ new Map();
        #refCount = /* @__PURE__ */ new Map();
        eventTarget = new EventTarget();
        constructor({ loadText, loadBlob, resources }) {
          this.loadText = loadText;
          this.loadBlob = loadBlob;
          this.manifest = resources.manifest;
          this.assets = resources.manifest;
        }
        async createURL(href, data, type, parent) {
          if (!data) return "";
          const detail = { data, type };
          Object.defineProperty(detail, "name", { value: href });
          const event = new CustomEvent("data", { detail });
          this.eventTarget.dispatchEvent(event);
          const newData = await event.detail.data;
          const newType = await event.detail.type;
          const url = URL.createObjectURL(new Blob([newData], { type: newType }));
          this.#cache.set(href, url);
          this.#refCount.set(href, 1);
          if (parent) {
            const childList = this.#children.get(parent);
            if (childList) childList.push(href);
            else this.#children.set(parent, [href]);
          }
          return url;
        }
        ref(href, parent) {
          const childList = this.#children.get(parent);
          if (!childList?.includes(href)) {
            this.#refCount.set(href, this.#refCount.get(href) + 1);
            if (childList) childList.push(href);
            else this.#children.set(parent, [href]);
          }
          return this.#cache.get(href);
        }
        unref(href) {
          if (!this.#refCount.has(href)) return;
          const count = this.#refCount.get(href) - 1;
          if (count < 1) {
            URL.revokeObjectURL(this.#cache.get(href));
            this.#cache.delete(href);
            this.#refCount.delete(href);
            const childList = this.#children.get(href);
            if (childList) while (childList.length) this.unref(childList.pop());
            this.#children.delete(href);
          } else this.#refCount.set(href, count);
        }
        // load manifest item, recursively loading all resources as needed
        async loadItem(item, parents = []) {
          if (!item) return null;
          const { href, mediaType } = item;
          const isScript = MIME.JS.test(item.mediaType);
          const detail = { type: mediaType, isScript, allow: true };
          const event = new CustomEvent("load", { detail });
          this.eventTarget.dispatchEvent(event);
          const allow = await event.detail.allow;
          if (!allow) return null;
          const parent = parents.at(-1);
          if (this.#cache.has(href)) return this.ref(href, parent);
          const shouldReplace = (isScript || [MIME.XHTML, MIME.HTML, MIME.CSS, MIME.SVG].includes(mediaType)) && parents.every((p3) => p3 !== href);
          if (shouldReplace) return this.loadReplaced(item, parents);
          const tryLoadBlob = Promise.resolve().then(() => this.loadBlob(href));
          return this.createURL(href, tryLoadBlob, mediaType, parent);
        }
        async loadHref(href, base, parents = []) {
          if (isExternal(href)) return href;
          const path = resolveURL(href, base);
          const item = this.manifest.find((item2) => item2.href === path);
          if (!item) return href;
          return this.loadItem(item, parents.concat(base));
        }
        async loadReplaced(item, parents = []) {
          const { href, mediaType } = item;
          const parent = parents.at(-1);
          let str = "";
          try {
            str = await this.loadText(href);
          } catch (e3) {
            return this.createURL(href, Promise.reject(e3), mediaType, parent);
          }
          if (!str) return null;
          if ([MIME.XHTML, MIME.HTML, MIME.SVG].includes(mediaType)) {
            let doc = new DOMParser().parseFromString(str, mediaType);
            if (mediaType === MIME.XHTML && (doc.querySelector("parsererror") || !doc.documentElement?.namespaceURI)) {
              console.warn(doc.querySelector("parsererror")?.innerText ?? "Invalid XHTML");
              item.mediaType = MIME.HTML;
              doc = new DOMParser().parseFromString(str, item.mediaType);
            }
            if ([MIME.XHTML, MIME.SVG].includes(item.mediaType)) {
              let child = doc.firstChild;
              while (child instanceof ProcessingInstruction) {
                if (child.data) {
                  const replacedData = await replaceSeries(
                    child.data,
                    /(?:^|\s*)(href\s*=\s*['"])([^'"]*)(['"])/i,
                    (_2, p1, p22, p3) => this.loadHref(p22, href, parents).then((p23) => `${p1}${p23}${p3}`)
                  );
                  child.replaceWith(doc.createProcessingInstruction(
                    child.target,
                    replacedData
                  ));
                }
                child = child.nextSibling;
              }
            }
            const replace = async (el, attr) => el.setAttribute(
              attr,
              await this.loadHref(el.getAttribute(attr), href, parents)
            );
            for (const el of doc.querySelectorAll("link[href]")) await replace(el, "href");
            for (const el of doc.querySelectorAll("[src]")) await replace(el, "src");
            for (const el of doc.querySelectorAll("[poster]")) await replace(el, "poster");
            for (const el of doc.querySelectorAll("object[data]")) await replace(el, "data");
            for (const el of doc.querySelectorAll("[*|href]:not([href])"))
              el.setAttributeNS(NS.XLINK, "href", await this.loadHref(
                el.getAttributeNS(NS.XLINK, "href"),
                href,
                parents
              ));
            for (const el of doc.querySelectorAll("[srcset]"))
              el.setAttribute("srcset", await replaceSeries(
                el.getAttribute("srcset"),
                /(\s*)(.+?)\s*((?:\s[\d.]+[wx])+\s*(?:,|$)|,\s+|$)/g,
                (_2, p1, p22, p3) => this.loadHref(p22, href, parents).then((p23) => `${p1}${p23}${p3}`)
              ));
            for (const el of doc.querySelectorAll("style"))
              if (el.textContent) el.textContent = await this.replaceCSS(el.textContent, href, parents);
            for (const el of doc.querySelectorAll("[style]"))
              el.setAttribute(
                "style",
                await this.replaceCSS(el.getAttribute("style"), href, parents)
              );
            const result2 = new XMLSerializer().serializeToString(doc);
            return this.createURL(href, result2, item.mediaType, parent);
          }
          const result = mediaType === MIME.CSS ? await this.replaceCSS(str, href, parents) : await this.replaceString(str, href, parents);
          return this.createURL(href, result, mediaType, parent);
        }
        async replaceCSS(str, href, parents = []) {
          const replacedUrls = await replaceSeries(
            str,
            /url\(\s*["']?([^'"\n]*?)\s*["']?\s*\)/gi,
            (_2, url) => this.loadHref(url, href, parents).then((url2) => `url("${url2}")`)
          );
          return replaceSeries(
            replacedUrls,
            /@import\s*["']([^"'\n]*?)["']/gi,
            (_2, url) => this.loadHref(url, href, parents).then((url2) => `@import "${url2}"`)
          );
        }
        // find & replace all possible relative paths for all assets without parsing
        replaceString(str, href, parents = []) {
          const assetMap = /* @__PURE__ */ new Map();
          const urls = this.assets.map((asset) => {
            if (asset.href === href) return;
            const relative = pathRelative(pathDirname(href), asset.href);
            const relativeEnc = encodeURI(relative);
            const rootRelative = "/" + asset.href;
            const rootRelativeEnc = encodeURI(rootRelative);
            const set = /* @__PURE__ */ new Set([relative, relativeEnc, rootRelative, rootRelativeEnc]);
            for (const url of set) assetMap.set(url, asset);
            return Array.from(set);
          }).flat().filter((x3) => x3);
          if (!urls.length) return str;
          const regex = new RegExp(urls.map(regexEscape).join("|"), "g");
          return replaceSeries(str, regex, async (match) => this.loadItem(
            assetMap.get(match.replace(/^\//, "")),
            parents.concat(href)
          ));
        }
        unloadItem(item) {
          this.unref(item?.href);
        }
        destroy() {
          for (const url of this.#cache.values()) URL.revokeObjectURL(url);
        }
      };
      getHTMLFragment = (doc, id) => doc.getElementById(id) ?? doc.querySelector(`[name="${CSS.escape(id)}"]`);
      getPageSpread = (properties) => {
        for (const p3 of properties) {
          if (p3 === "page-spread-left" || p3 === "rendition:page-spread-left")
            return "left";
          if (p3 === "page-spread-right" || p3 === "rendition:page-spread-right")
            return "right";
          if (p3 === "rendition:page-spread-center") return "center";
        }
      };
      getDisplayOptions = (doc) => {
        if (!doc) return null;
        return {
          fixedLayout: getElementText(doc.querySelector('option[name="fixed-layout"]')),
          openToSpread: getElementText(doc.querySelector('option[name="open-to-spread"]'))
        };
      };
      EPUB = class {
        parser = new DOMParser();
        #loader;
        #encryption;
        constructor({ loadText, loadBlob, getSize, sha1 }) {
          this.loadText = loadText;
          this.loadBlob = loadBlob;
          this.getSize = getSize;
          this.#encryption = new Encryption(deobfuscators(sha1));
        }
        async #loadXML(uri) {
          const str = await this.loadText(uri);
          if (!str) return null;
          const doc = this.parser.parseFromString(str, MIME.XML);
          if (doc.querySelector("parsererror"))
            throw new Error(`XML parsing error: ${uri}
${doc.querySelector("parsererror").innerText}`);
          return doc;
        }
        async init() {
          const $container = await this.#loadXML("META-INF/container.xml");
          if (!$container) throw new Error("Failed to load container file");
          const opfs = Array.from(
            $container.getElementsByTagNameNS(NS.CONTAINER, "rootfile"),
            getAttributes("full-path", "media-type")
          ).filter((file) => file.mediaType === "application/oebps-package+xml");
          if (!opfs.length) throw new Error("No package document defined in container");
          const opfPath = opfs[0].fullPath;
          const opf = await this.#loadXML(opfPath);
          if (!opf) throw new Error("Failed to load package document");
          const $encryption = await this.#loadXML("META-INF/encryption.xml");
          await this.#encryption.init($encryption, opf);
          this.resources = new Resources({
            opf,
            resolveHref: (url) => resolveURL(url, opfPath)
          });
          this.#loader = new Loader({
            loadText: this.loadText,
            loadBlob: (uri) => Promise.resolve(this.loadBlob(uri)).then(this.#encryption.getDecoder(uri)),
            resources: this.resources
          });
          this.transformTarget = this.#loader.eventTarget;
          this.sections = this.resources.spine.map((spineItem, index) => {
            const { idref, linear, properties = [] } = spineItem;
            const item = this.resources.getItemByID(idref);
            if (!item) {
              console.warn(`Could not find item with ID "${idref}" in manifest`);
              return null;
            }
            return {
              id: item.href,
              load: () => this.#loader.loadItem(item),
              unload: () => this.#loader.unloadItem(item),
              createDocument: () => this.loadDocument(item),
              size: this.getSize(item.href),
              cfi: this.resources.cfis[index],
              linear,
              pageSpread: getPageSpread(properties),
              resolveHref: (href) => resolveURL(href, item.href),
              mediaOverlay: item.mediaOverlay ? this.resources.getItemByID(item.mediaOverlay) : null
            };
          }).filter((s3) => s3);
          const { navPath, ncxPath } = this.resources;
          if (navPath) try {
            const resolve = (url) => resolveURL(url, navPath);
            const nav = parseNav(await this.#loadXML(navPath), resolve);
            this.toc = nav.toc;
            this.pageList = nav.pageList;
            this.landmarks = nav.landmarks;
          } catch (e3) {
            console.warn(e3);
          }
          if (!this.toc && ncxPath) try {
            const resolve = (url) => resolveURL(url, ncxPath);
            const ncx = parseNCX(await this.#loadXML(ncxPath), resolve);
            this.toc = ncx.toc;
            this.pageList = ncx.pageList;
          } catch (e3) {
            console.warn(e3);
          }
          this.landmarks ??= this.resources.guide;
          const { metadata, rendition, media } = getMetadata(opf);
          this.metadata = metadata;
          this.rendition = rendition;
          this.media = media;
          this.dir = this.resources.pageProgressionDirection;
          const displayOptions = getDisplayOptions(
            await this.#loadXML("META-INF/com.apple.ibooks.display-options.xml") ?? await this.#loadXML("META-INF/com.kobobooks.display-options.xml")
          );
          if (displayOptions) {
            if (displayOptions.fixedLayout === "true")
              this.rendition.layout ??= "pre-paginated";
            if (displayOptions.openToSpread === "false") this.sections.find((section) => section.linear !== "no").pageSpread ??= this.dir === "rtl" ? "left" : "right";
          }
          return this;
        }
        async loadDocument(item) {
          const str = await this.loadText(item.href);
          return this.parser.parseFromString(str, item.mediaType);
        }
        getMediaOverlay() {
          return new MediaOverlay(this, this.#loadXML.bind(this));
        }
        resolveCFI(cfi) {
          return this.resources.resolveCFI(cfi);
        }
        resolveHref(href) {
          const [path, hash] = href.split("#");
          const item = this.resources.getItemByHref(decodeURI(path));
          if (!item) return null;
          const index = this.resources.spine.findIndex(({ idref }) => idref === item.id);
          const anchor = hash ? (doc) => getHTMLFragment(doc, hash) : () => 0;
          return { index, anchor };
        }
        splitTOCHref(href) {
          return href?.split("#") ?? [];
        }
        getTOCFragment(doc, id) {
          return doc.getElementById(id) ?? doc.querySelector(`[name="${CSS.escape(id)}"]`);
        }
        isExternal(uri) {
          return isExternal(uri);
        }
        async getCover() {
          const cover = this.resources?.cover;
          return cover?.href ? new Blob([await this.loadBlob(cover.href)], { type: cover.mediaType }) : null;
        }
        async getCalibreBookmarks() {
          const txt = await this.loadText("META-INF/calibre_bookmarks.txt");
          const magic = "encoding=json+base64:";
          if (txt?.startsWith(magic)) {
            const json = atob(txt.slice(magic.length));
            return JSON.parse(json);
          }
        }
        destroy() {
          this.#loader?.destroy();
        }
      };
    }
  });

  // comic-book.js
  var comic_book_exports = {};
  __export(comic_book_exports, {
    makeComicBook: () => makeComicBook
  });
  var makeComicBook;
  var init_comic_book = __esm({
    "comic-book.js"() {
      makeComicBook = () => {
        throw new Error("not supported");
      };
    }
  });

  // fb2.js
  var fb2_exports = {};
  __export(fb2_exports, {
    makeFB2: () => makeFB2
  });
  var makeFB2;
  var init_fb2 = __esm({
    "fb2.js"() {
      makeFB2 = () => {
        throw new Error("not supported");
      };
    }
  });

  // pdf.js
  var pdf_exports = {};
  __export(pdf_exports, {
    makePDF: () => makePDF
  });
  var makePDF;
  var init_pdf = __esm({
    "pdf.js"() {
      makePDF = () => {
        throw new Error("not supported");
      };
    }
  });

  // mobi.js
  var mobi_exports = {};
  __export(mobi_exports, {
    MOBI: () => MOBI,
    isMOBI: () => isMOBI
  });
  function rawBytesToString(uint8Array) {
    const chunkSize = 32768;
    let result = "";
    for (let i3 = 0; i3 < uint8Array.length; i3 += chunkSize) {
      result += String.fromCharCode.apply(null, uint8Array.subarray(i3, i3 + chunkSize));
    }
    return result;
  }
  var unescapeHTML, MIME2, PDB_HEADER, PALMDOC_HEADER, MOBI_HEADER, KF8_HEADER, EXTH_HEADER, INDX_HEADER, TAGX_HEADER, HUFF_HEADER, CDIC_HEADER, FDST_HEADER, FONT_HEADER, MOBI_ENCODING, EXTH_RECORD_TYPE, MOBI_LANG, concatTypedArray, concatTypedArray3, decoder, getString, getUint, getStruct, getDecoder, getVarLen, getVarLenFromEnd, countBitsSet, countUnsetEnd, decompressPalmDOC, read32Bits, huffcdic, getIndexData, getNCX, getEXTH, getFont, isMOBI, PDB, MOBI, mbpPagebreakRegex, fileposRegex, getIndent, MOBI6, kindleResourceRegex, kindlePosRegex, parseResourceURI, parsePosURI, makePosURI, getFragmentSelector, replaceSeries2, getPageSpread2, KF8;
  var init_mobi = __esm({
    "mobi.js"() {
      unescapeHTML = (str) => {
        if (!str) return "";
        const textarea = document.createElement("textarea");
        textarea.innerHTML = str;
        return textarea.value;
      };
      MIME2 = {
        XML: "application/xml",
        XHTML: "application/xhtml+xml",
        HTML: "text/html",
        CSS: "text/css",
        SVG: "image/svg+xml"
      };
      PDB_HEADER = {
        name: [0, 32, "string"],
        type: [60, 4, "string"],
        creator: [64, 4, "string"],
        numRecords: [76, 2, "uint"]
      };
      PALMDOC_HEADER = {
        compression: [0, 2, "uint"],
        numTextRecords: [8, 2, "uint"],
        recordSize: [10, 2, "uint"],
        encryption: [12, 2, "uint"]
      };
      MOBI_HEADER = {
        magic: [16, 4, "string"],
        length: [20, 4, "uint"],
        type: [24, 4, "uint"],
        encoding: [28, 4, "uint"],
        uid: [32, 4, "uint"],
        version: [36, 4, "uint"],
        titleOffset: [84, 4, "uint"],
        titleLength: [88, 4, "uint"],
        localeRegion: [94, 1, "uint"],
        localeLanguage: [95, 1, "uint"],
        resourceStart: [108, 4, "uint"],
        huffcdic: [112, 4, "uint"],
        numHuffcdic: [116, 4, "uint"],
        exthFlag: [128, 4, "uint"],
        trailingFlags: [240, 4, "uint"],
        indx: [244, 4, "uint"]
      };
      KF8_HEADER = {
        resourceStart: [108, 4, "uint"],
        fdst: [192, 4, "uint"],
        numFdst: [196, 4, "uint"],
        frag: [248, 4, "uint"],
        skel: [252, 4, "uint"],
        guide: [260, 4, "uint"]
      };
      EXTH_HEADER = {
        magic: [0, 4, "string"],
        length: [4, 4, "uint"],
        count: [8, 4, "uint"]
      };
      INDX_HEADER = {
        magic: [0, 4, "string"],
        length: [4, 4, "uint"],
        type: [8, 4, "uint"],
        idxt: [20, 4, "uint"],
        numRecords: [24, 4, "uint"],
        encoding: [28, 4, "uint"],
        language: [32, 4, "uint"],
        total: [36, 4, "uint"],
        ordt: [40, 4, "uint"],
        ligt: [44, 4, "uint"],
        numLigt: [48, 4, "uint"],
        numCncx: [52, 4, "uint"]
      };
      TAGX_HEADER = {
        magic: [0, 4, "string"],
        length: [4, 4, "uint"],
        numControlBytes: [8, 4, "uint"]
      };
      HUFF_HEADER = {
        magic: [0, 4, "string"],
        offset1: [8, 4, "uint"],
        offset2: [12, 4, "uint"]
      };
      CDIC_HEADER = {
        magic: [0, 4, "string"],
        length: [4, 4, "uint"],
        numEntries: [8, 4, "uint"],
        codeLength: [12, 4, "uint"]
      };
      FDST_HEADER = {
        magic: [0, 4, "string"],
        numEntries: [8, 4, "uint"]
      };
      FONT_HEADER = {
        flags: [8, 4, "uint"],
        dataStart: [12, 4, "uint"],
        keyLength: [16, 4, "uint"],
        keyStart: [20, 4, "uint"]
      };
      MOBI_ENCODING = {
        1252: "windows-1252",
        65001: "utf-8"
      };
      EXTH_RECORD_TYPE = {
        100: ["creator", "string", true],
        101: ["publisher"],
        103: ["description"],
        104: ["isbn"],
        105: ["subject", "string", true],
        106: ["date"],
        108: ["contributor", "string", true],
        109: ["rights"],
        110: ["subjectCode", "string", true],
        112: ["source", "string", true],
        113: ["asin"],
        121: ["boundary", "uint"],
        122: ["fixedLayout"],
        125: ["numResources", "uint"],
        126: ["originalResolution"],
        127: ["zeroGutter"],
        128: ["zeroMargin"],
        129: ["coverURI"],
        132: ["regionMagnification"],
        201: ["coverOffset", "uint"],
        202: ["thumbnailOffset", "uint"],
        503: ["title"],
        524: ["language", "string", true],
        527: ["pageProgressionDirection"]
      };
      MOBI_LANG = {
        1: [
          "ar",
          "ar-SA",
          "ar-IQ",
          "ar-EG",
          "ar-LY",
          "ar-DZ",
          "ar-MA",
          "ar-TN",
          "ar-OM",
          "ar-YE",
          "ar-SY",
          "ar-JO",
          "ar-LB",
          "ar-KW",
          "ar-AE",
          "ar-BH",
          "ar-QA"
        ],
        2: ["bg"],
        3: ["ca"],
        4: ["zh", "zh-TW", "zh-CN", "zh-HK", "zh-SG"],
        5: ["cs"],
        6: ["da"],
        7: ["de", "de-DE", "de-CH", "de-AT", "de-LU", "de-LI"],
        8: ["el"],
        9: [
          "en",
          "en-US",
          "en-GB",
          "en-AU",
          "en-CA",
          "en-NZ",
          "en-IE",
          "en-ZA",
          "en-JM",
          null,
          "en-BZ",
          "en-TT",
          "en-ZW",
          "en-PH"
        ],
        10: [
          "es",
          "es-ES",
          "es-MX",
          null,
          "es-GT",
          "es-CR",
          "es-PA",
          "es-DO",
          "es-VE",
          "es-CO",
          "es-PE",
          "es-AR",
          "es-EC",
          "es-CL",
          "es-UY",
          "es-PY",
          "es-BO",
          "es-SV",
          "es-HN",
          "es-NI",
          "es-PR"
        ],
        11: ["fi"],
        12: ["fr", "fr-FR", "fr-BE", "fr-CA", "fr-CH", "fr-LU", "fr-MC"],
        13: ["he"],
        14: ["hu"],
        15: ["is"],
        16: ["it", "it-IT", "it-CH"],
        17: ["ja"],
        18: ["ko"],
        19: ["nl", "nl-NL", "nl-BE"],
        20: ["no", "nb", "nn"],
        21: ["pl"],
        22: ["pt", "pt-BR", "pt-PT"],
        23: ["rm"],
        24: ["ro"],
        25: ["ru"],
        26: ["hr", null, "sr"],
        27: ["sk"],
        28: ["sq"],
        29: ["sv", "sv-SE", "sv-FI"],
        30: ["th"],
        31: ["tr"],
        32: ["ur"],
        33: ["id"],
        34: ["uk"],
        35: ["be"],
        36: ["sl"],
        37: ["et"],
        38: ["lv"],
        39: ["lt"],
        41: ["fa"],
        42: ["vi"],
        43: ["hy"],
        44: ["az"],
        45: ["eu"],
        46: ["hsb"],
        47: ["mk"],
        48: ["st"],
        49: ["ts"],
        50: ["tn"],
        52: ["xh"],
        53: ["zu"],
        54: ["af"],
        55: ["ka"],
        56: ["fo"],
        57: ["hi"],
        58: ["mt"],
        59: ["se"],
        62: ["ms"],
        63: ["kk"],
        65: ["sw"],
        67: ["uz", null, "uz-UZ"],
        68: ["tt"],
        69: ["bn"],
        70: ["pa"],
        71: ["gu"],
        72: ["or"],
        73: ["ta"],
        74: ["te"],
        75: ["kn"],
        76: ["ml"],
        77: ["as"],
        78: ["mr"],
        79: ["sa"],
        82: ["cy", "cy-GB"],
        83: ["gl", "gl-ES"],
        87: ["kok"],
        97: ["ne"],
        98: ["fy"]
      };
      concatTypedArray = (a3, b3) => {
        const result = new a3.constructor(a3.length + b3.length);
        result.set(a3);
        result.set(b3, a3.length);
        return result;
      };
      concatTypedArray3 = (a3, b3, c2) => {
        const result = new a3.constructor(a3.length + b3.length + c2.length);
        result.set(a3);
        result.set(b3, a3.length);
        result.set(c2, a3.length + b3.length);
        return result;
      };
      decoder = new TextDecoder();
      getString = (buffer) => decoder.decode(buffer);
      getUint = (buffer) => {
        if (!buffer) return;
        const l3 = buffer.byteLength;
        const func = l3 === 4 ? "getUint32" : l3 === 2 ? "getUint16" : "getUint8";
        return new DataView(buffer)[func](0);
      };
      getStruct = (def, buffer) => Object.fromEntries(Array.from(Object.entries(def)).map(([key, [start, len, type]]) => [
        key,
        (type === "string" ? getString : getUint)(buffer.slice(start, start + len))
      ]));
      getDecoder = (x3) => new TextDecoder(MOBI_ENCODING[x3]);
      getVarLen = (byteArray, i3 = 0) => {
        let value = 0, length = 0;
        for (const byte of byteArray.subarray(i3, i3 + 4)) {
          value = value << 7 | (byte & 127) >>> 0;
          length++;
          if (byte & 128) break;
        }
        return { value, length };
      };
      getVarLenFromEnd = (byteArray) => {
        let value = 0;
        for (const byte of byteArray.subarray(-4)) {
          if (byte & 128) value = 0;
          value = value << 7 | byte & 127;
        }
        return value;
      };
      countBitsSet = (x3) => {
        let count = 0;
        for (; x3 > 0; x3 = x3 >> 1) if ((x3 & 1) === 1) count++;
        return count;
      };
      countUnsetEnd = (x3) => {
        let count = 0;
        while ((x3 & 1) === 0) x3 = x3 >> 1, count++;
        return count;
      };
      decompressPalmDOC = (array) => {
        let output = [];
        for (let i3 = 0; i3 < array.length; i3++) {
          const byte = array[i3];
          if (byte === 0) output.push(0);
          else if (byte <= 8)
            for (const x3 of array.subarray(i3 + 1, (i3 += byte) + 1))
              output.push(x3);
          else if (byte <= 127) output.push(byte);
          else if (byte <= 191) {
            const bytes = byte << 8 | array[i3++ + 1];
            const distance = (bytes & 16383) >>> 3;
            const length = (bytes & 7) + 3;
            for (let j2 = 0; j2 < length; j2++)
              output.push(output[output.length - distance]);
          } else output.push(32, byte ^ 128);
        }
        return Uint8Array.from(output);
      };
      read32Bits = (byteArray, from) => {
        const startByte = from >> 3;
        const end = from + 32;
        const endByte = end >> 3;
        let bits = 0n;
        for (let i3 = startByte; i3 <= endByte; i3++)
          bits = bits << 8n | BigInt(byteArray[i3] ?? 0);
        return bits >> 8n - BigInt(end & 7) & 0xffffffffn;
      };
      huffcdic = async (mobi, loadRecord) => {
        const huffRecord = await loadRecord(mobi.huffcdic);
        const { magic, offset1, offset2 } = getStruct(HUFF_HEADER, huffRecord);
        if (magic !== "HUFF") throw new Error("Invalid HUFF record");
        const table1 = Array.from({ length: 256 }, (_2, i3) => offset1 + i3 * 4).map((offset) => getUint(huffRecord.slice(offset, offset + 4))).map((x3) => [x3 & 128, x3 & 31, x3 >>> 8]);
        const table2 = [null].concat(Array.from({ length: 32 }, (_2, i3) => offset2 + i3 * 8).map((offset) => [
          getUint(huffRecord.slice(offset, offset + 4)),
          getUint(huffRecord.slice(offset + 4, offset + 8))
        ]));
        const dictionary = [];
        for (let i3 = 1; i3 < mobi.numHuffcdic; i3++) {
          const record = await loadRecord(mobi.huffcdic + i3);
          const cdic = getStruct(CDIC_HEADER, record);
          if (cdic.magic !== "CDIC") throw new Error("Invalid CDIC record");
          const n3 = Math.min(1 << cdic.codeLength, cdic.numEntries - dictionary.length);
          const buffer = record.slice(cdic.length);
          for (let i4 = 0; i4 < n3; i4++) {
            const offset = getUint(buffer.slice(i4 * 2, i4 * 2 + 2));
            const x3 = getUint(buffer.slice(offset, offset + 2));
            const length = x3 & 32767;
            const decompressed = x3 & 32768;
            const value = new Uint8Array(
              buffer.slice(offset + 2, offset + 2 + length)
            );
            dictionary.push([value, decompressed]);
          }
        }
        const decompress = (byteArray) => {
          let output = new Uint8Array();
          const bitLength = byteArray.byteLength * 8;
          for (let i3 = 0; i3 < bitLength; ) {
            const bits = Number(read32Bits(byteArray, i3));
            let [found, codeLength, value] = table1[bits >>> 24];
            if (!found) {
              while (bits >>> 32 - codeLength < table2[codeLength][0])
                codeLength += 1;
              value = table2[codeLength][1];
            }
            if ((i3 += codeLength) > bitLength) break;
            const code = value - (bits >>> 32 - codeLength);
            let [result, decompressed] = dictionary[code];
            if (!decompressed) {
              result = decompress(result);
              dictionary[code] = [result, true];
            }
            output = concatTypedArray(output, result);
          }
          return output;
        };
        return decompress;
      };
      getIndexData = async (indxIndex, loadRecord) => {
        const indxRecord = await loadRecord(indxIndex);
        const indx = getStruct(INDX_HEADER, indxRecord);
        if (indx.magic !== "INDX") throw new Error("Invalid INDX record");
        const decoder2 = getDecoder(indx.encoding);
        const tagxBuffer = indxRecord.slice(indx.length);
        const tagx = getStruct(TAGX_HEADER, tagxBuffer);
        if (tagx.magic !== "TAGX") throw new Error("Invalid TAGX section");
        const numTags = (tagx.length - 12) / 4;
        const tagTable = Array.from({ length: numTags }, (_2, i3) => new Uint8Array(tagxBuffer.slice(12 + i3 * 4, 12 + i3 * 4 + 4)));
        const cncx = {};
        let cncxRecordOffset = 0;
        for (let i3 = 0; i3 < indx.numCncx; i3++) {
          const record = await loadRecord(indxIndex + indx.numRecords + i3 + 1);
          const array = new Uint8Array(record);
          for (let pos = 0; pos < array.byteLength; ) {
            const index = pos;
            const { value, length } = getVarLen(array, pos);
            pos += length;
            const result = record.slice(pos, pos + value);
            pos += value;
            cncx[cncxRecordOffset + index] = decoder2.decode(result);
          }
          cncxRecordOffset += 65536;
        }
        const table = [];
        for (let i3 = 0; i3 < indx.numRecords; i3++) {
          const record = await loadRecord(indxIndex + 1 + i3);
          const array = new Uint8Array(record);
          const indx2 = getStruct(INDX_HEADER, record);
          if (indx2.magic !== "INDX") throw new Error("Invalid INDX record");
          for (let j2 = 0; j2 < indx2.numRecords; j2++) {
            const offsetOffset = indx2.idxt + 4 + 2 * j2;
            const offset = getUint(record.slice(offsetOffset, offsetOffset + 2));
            const length = getUint(record.slice(offset, offset + 1));
            const name = getString(record.slice(offset + 1, offset + 1 + length));
            const tags = [];
            const startPos = offset + 1 + length;
            let controlByteIndex = 0;
            let pos = startPos + tagx.numControlBytes;
            for (const [tag, numValues, mask, end] of tagTable) {
              if (end & 1) {
                controlByteIndex++;
                continue;
              }
              const offset2 = startPos + controlByteIndex;
              const value = getUint(record.slice(offset2, offset2 + 1)) & mask;
              if (value === mask) {
                if (countBitsSet(mask) > 1) {
                  const { value: value2, length: length2 } = getVarLen(array, pos);
                  tags.push([tag, null, value2, numValues]);
                  pos += length2;
                } else tags.push([tag, 1, null, numValues]);
              } else tags.push([tag, value >> countUnsetEnd(mask), null, numValues]);
            }
            const tagMap = {};
            for (const [tag, valueCount, valueBytes, numValues] of tags) {
              const values = [];
              if (valueCount != null) {
                for (let i4 = 0; i4 < valueCount * numValues; i4++) {
                  const { value, length: length2 } = getVarLen(array, pos);
                  values.push(value);
                  pos += length2;
                }
              } else {
                let count = 0;
                while (count < valueBytes) {
                  const { value, length: length2 } = getVarLen(array, pos);
                  values.push(value);
                  pos += length2;
                  count += length2;
                }
              }
              tagMap[tag] = values;
            }
            table.push({ name, tagMap });
          }
        }
        return { table, cncx };
      };
      getNCX = async (indxIndex, loadRecord) => {
        const { table, cncx } = await getIndexData(indxIndex, loadRecord);
        const items = table.map(({ tagMap }, index) => ({
          index,
          offset: tagMap[1]?.[0],
          size: tagMap[2]?.[0],
          label: cncx[tagMap[3]] ?? "",
          headingLevel: tagMap[4]?.[0],
          pos: tagMap[6],
          parent: tagMap[21]?.[0],
          firstChild: tagMap[22]?.[0],
          lastChild: tagMap[23]?.[0]
        }));
        const getChildren = (item) => {
          if (item.firstChild == null) return item;
          item.children = items.filter((x3) => x3.parent === item.index).map(getChildren);
          return item;
        };
        return items.filter((item) => item.headingLevel === 0).map(getChildren);
      };
      getEXTH = (buf, encoding) => {
        const { magic, count } = getStruct(EXTH_HEADER, buf);
        if (magic !== "EXTH") throw new Error("Invalid EXTH header");
        const decoder2 = getDecoder(encoding);
        const results = {};
        let offset = 12;
        for (let i3 = 0; i3 < count; i3++) {
          const type = getUint(buf.slice(offset, offset + 4));
          const length = getUint(buf.slice(offset + 4, offset + 8));
          if (type in EXTH_RECORD_TYPE) {
            const [name, typ, many] = EXTH_RECORD_TYPE[type];
            const data = buf.slice(offset + 8, offset + length);
            const value = typ === "uint" ? getUint(data) : decoder2.decode(data);
            if (many) {
              results[name] ??= [];
              results[name].push(value);
            } else results[name] = value;
          }
          offset += length;
        }
        return results;
      };
      getFont = async (buf, unzlib) => {
        const { flags, dataStart, keyLength, keyStart } = getStruct(FONT_HEADER, buf);
        const array = new Uint8Array(buf.slice(dataStart));
        if (flags & 2) {
          const bytes = keyLength === 16 ? 1024 : 1040;
          const key = new Uint8Array(buf.slice(keyStart, keyStart + keyLength));
          const length = Math.min(bytes, array.length);
          for (var i3 = 0; i3 < length; i3++) array[i3] = array[i3] ^ key[i3 % key.length];
        }
        if (flags & 1) try {
          return await unzlib(array);
        } catch (e3) {
          console.warn(e3);
          console.warn("Failed to decompress font");
        }
        return array;
      };
      isMOBI = async (file) => {
        const magic = getString(await file.slice(60, 68).arrayBuffer());
        return magic === "BOOKMOBI";
      };
      PDB = class {
        #file;
        #offsets;
        pdb;
        async open(file) {
          this.#file = file;
          const pdb = getStruct(PDB_HEADER, await file.slice(0, 78).arrayBuffer());
          this.pdb = pdb;
          const buffer = await file.slice(78, 78 + pdb.numRecords * 8).arrayBuffer();
          this.#offsets = Array.from(
            { length: pdb.numRecords },
            (_2, i3) => getUint(buffer.slice(i3 * 8, i3 * 8 + 4))
          ).map((x3, i3, a3) => [x3, a3[i3 + 1]]);
        }
        loadRecord(index) {
          const offsets = this.#offsets[index];
          if (!offsets) throw new RangeError("Record index out of bounds");
          return this.#file.slice(...offsets).arrayBuffer();
        }
        async loadMagic(index) {
          const start = this.#offsets[index][0];
          return getString(await this.#file.slice(start, start + 4).arrayBuffer());
        }
      };
      MOBI = class extends PDB {
        #start = 0;
        #resourceStart;
        #decoder;
        #encoder;
        #decompress;
        #removeTrailingEntries;
        constructor({ unzlib }) {
          super();
          this.unzlib = unzlib;
        }
        async open(file) {
          await super.open(file);
          this.headers = this.#getHeaders(await super.loadRecord(0));
          this.#resourceStart = this.headers.mobi.resourceStart;
          let isKF8 = this.headers.mobi.version >= 8;
          if (!isKF8) {
            const boundary = this.headers.exth?.boundary;
            if (boundary < 4294967295) try {
              this.headers = this.#getHeaders(await super.loadRecord(boundary));
              this.#start = boundary;
              isKF8 = true;
            } catch (e3) {
              console.warn(e3);
              console.warn("Failed to open KF8; falling back to MOBI");
            }
          }
          await this.#setup();
          return isKF8 ? new KF8(this).init() : new MOBI6(this).init();
        }
        #getHeaders(buf) {
          const palmdoc = getStruct(PALMDOC_HEADER, buf);
          const mobi = getStruct(MOBI_HEADER, buf);
          if (mobi.magic !== "MOBI") throw new Error("Missing MOBI header");
          const { titleOffset, titleLength, localeLanguage, localeRegion } = mobi;
          mobi.title = buf.slice(titleOffset, titleOffset + titleLength);
          const lang = MOBI_LANG[localeLanguage];
          mobi.language = lang?.[localeRegion >> 2] ?? lang?.[0];
          const exth = mobi.exthFlag & 64 ? getEXTH(buf.slice(mobi.length + 16), mobi.encoding) : null;
          const kf8 = mobi.version >= 8 ? getStruct(KF8_HEADER, buf) : null;
          return { palmdoc, mobi, exth, kf8 };
        }
        async #setup() {
          const { palmdoc, mobi } = this.headers;
          this.#decoder = getDecoder(mobi.encoding);
          this.#encoder = new TextEncoder();
          const { compression } = palmdoc;
          this.#decompress = compression === 1 ? (f3) => f3 : compression === 2 ? decompressPalmDOC : compression === 17480 ? await huffcdic(mobi, this.loadRecord.bind(this)) : null;
          if (!this.#decompress) throw new Error("Unknown compression type");
          const { trailingFlags } = mobi;
          const multibyte = trailingFlags & 1;
          const numTrailingEntries = countBitsSet(trailingFlags >>> 1);
          this.#removeTrailingEntries = (array) => {
            for (let i3 = 0; i3 < numTrailingEntries; i3++) {
              const length = getVarLenFromEnd(array);
              array = array.subarray(0, -length);
            }
            if (multibyte) {
              const length = (array[array.length - 1] & 3) + 1;
              array = array.subarray(0, -length);
            }
            return array;
          };
        }
        decode(...args) {
          return this.#decoder.decode(...args);
        }
        encode(...args) {
          return this.#encoder.encode(...args);
        }
        loadRecord(index) {
          return super.loadRecord(this.#start + index);
        }
        loadMagic(index) {
          return super.loadMagic(this.#start + index);
        }
        loadText(index) {
          return this.loadRecord(index + 1).then((buf) => new Uint8Array(buf)).then(this.#removeTrailingEntries).then(this.#decompress);
        }
        async loadResource(index) {
          const buf = await super.loadRecord(this.#resourceStart + index);
          const magic = getString(buf.slice(0, 4));
          if (magic === "FONT") return getFont(buf, this.unzlib);
          if (magic === "VIDE" || magic === "AUDI") return buf.slice(12);
          return buf;
        }
        getNCX() {
          const index = this.headers.mobi.indx;
          if (index < 4294967295) return getNCX(index, this.loadRecord.bind(this));
        }
        getMetadata() {
          const { mobi, exth } = this.headers;
          return {
            identifier: mobi.uid.toString(),
            title: unescapeHTML(exth?.title || this.decode(mobi.title)),
            author: exth?.creator?.map(unescapeHTML),
            publisher: unescapeHTML(exth?.publisher),
            language: exth?.language ?? mobi.language,
            published: exth?.date,
            description: unescapeHTML(exth?.description),
            subject: exth?.subject?.map(unescapeHTML),
            rights: unescapeHTML(exth?.rights),
            contributor: exth?.contributor
          };
        }
        async getCover() {
          const { exth } = this.headers;
          const offset = exth?.coverOffset < 4294967295 ? exth?.coverOffset : exth?.thumbnailOffset < 4294967295 ? exth?.thumbnailOffset : null;
          if (offset != null) {
            const buf = await this.loadResource(offset);
            return new Blob([buf]);
          }
        }
      };
      mbpPagebreakRegex = /<\s*(?:mbp:)?pagebreak[^>]*>/gi;
      fileposRegex = /<[^<>]+filepos=['"]{0,1}(\d+)[^<>]*>/gi;
      getIndent = (el) => {
        let x3 = 0;
        while (el) {
          const parent = el.parentElement;
          if (parent) {
            const tag = parent.tagName.toLowerCase();
            if (tag === "p") x3 += 1.5;
            else if (tag === "blockquote") x3 += 2;
          }
          el = parent;
        }
        return x3;
      };
      MOBI6 = class {
        parser = new DOMParser();
        serializer = new XMLSerializer();
        #resourceCache = /* @__PURE__ */ new Map();
        #textCache = /* @__PURE__ */ new Map();
        #cache = /* @__PURE__ */ new Map();
        #sections;
        #fileposList = [];
        #type = MIME2.HTML;
        constructor(mobi) {
          this.mobi = mobi;
        }
        async init() {
          const recordBuffers = [];
          for (let i3 = 0; i3 < this.mobi.headers.palmdoc.numTextRecords; i3++) {
            const buf = await this.mobi.loadText(i3);
            recordBuffers.push(buf);
          }
          const totalLength = recordBuffers.reduce((sum, buf) => sum + buf.byteLength, 0);
          const array = new Uint8Array(totalLength);
          recordBuffers.reduce((offset, buf) => {
            array.set(new Uint8Array(buf), offset);
            return offset + buf.byteLength;
          }, 0);
          const str = rawBytesToString(array);
          this.#sections = [0].concat(Array.from(str.matchAll(mbpPagebreakRegex), (m3) => m3.index)).map((start, i3, a3) => {
            const end = a3[i3 + 1] ?? array.length;
            return { book: this, raw: array.subarray(start, end) };
          }).map((section, i3, arr) => {
            section.start = arr[i3 - 1]?.end ?? 0;
            section.end = section.start + section.raw.byteLength;
            return section;
          });
          this.sections = this.#sections.map((section, index) => ({
            id: index,
            load: () => this.loadSection(section),
            createDocument: () => this.createDocument(section),
            size: section.end - section.start
          }));
          try {
            this.landmarks = await this.getGuide();
            const tocHref = this.landmarks.find(({ type }) => type?.includes("toc"))?.href;
            if (tocHref) {
              const { index } = this.resolveHref(tocHref);
              const doc = await this.sections[index].createDocument();
              let lastItem;
              let lastLevel = 0;
              let lastIndent = 0;
              const lastLevelOfIndent = /* @__PURE__ */ new Map();
              const lastParentOfLevel = /* @__PURE__ */ new Map();
              this.toc = Array.from(doc.querySelectorAll("a[filepos]")).reduce((arr, a3) => {
                const indent = getIndent(a3);
                const item = {
                  label: a3.innerText?.trim() ?? "",
                  href: `filepos:${a3.getAttribute("filepos")}`
                };
                const level = indent > lastIndent ? lastLevel + 1 : indent === lastIndent ? lastLevel : lastLevelOfIndent.get(indent) ?? Math.max(0, lastLevel - 1);
                if (level > lastLevel) {
                  if (lastItem) {
                    lastItem.subitems ??= [];
                    lastItem.subitems.push(item);
                    lastParentOfLevel.set(level, lastItem);
                  } else arr.push(item);
                } else {
                  const parent = lastParentOfLevel.get(level);
                  if (parent) parent.subitems.push(item);
                  else arr.push(item);
                }
                lastItem = item;
                lastLevel = level;
                lastIndent = indent;
                lastLevelOfIndent.set(indent, level);
                return arr;
              }, []);
            }
          } catch (e3) {
            console.warn(e3);
          }
          this.#fileposList = [...new Set(
            Array.from(str.matchAll(fileposRegex), (m3) => m3[1])
          )].map((filepos) => ({ filepos, number: Number(filepos) })).sort((a3, b3) => a3.number - b3.number);
          this.metadata = this.mobi.getMetadata();
          this.getCover = this.mobi.getCover.bind(this.mobi);
          return this;
        }
        async getGuide() {
          const doc = await this.createDocument(this.#sections[0]);
          return Array.from(doc.getElementsByTagName("reference"), (ref) => ({
            label: ref.getAttribute("title"),
            type: ref.getAttribute("type")?.split(/\s/),
            href: `filepos:${ref.getAttribute("filepos")}`
          }));
        }
        async loadResource(index) {
          if (this.#resourceCache.has(index)) return this.#resourceCache.get(index);
          const raw = await this.mobi.loadResource(index);
          const url = URL.createObjectURL(new Blob([raw]));
          this.#resourceCache.set(index, url);
          return url;
        }
        async loadRecindex(recindex) {
          return this.loadResource(Number(recindex) - 1);
        }
        async replaceResources(doc) {
          for (const img of doc.querySelectorAll("img[recindex]")) {
            const recindex = img.getAttribute("recindex");
            try {
              img.src = await this.loadRecindex(recindex);
            } catch {
              console.warn(`Failed to load image ${recindex}`);
            }
          }
          for (const media of doc.querySelectorAll("[mediarecindex]")) {
            const mediarecindex = media.getAttribute("mediarecindex");
            const recindex = media.getAttribute("recindex");
            try {
              media.src = await this.loadRecindex(mediarecindex);
              if (recindex) media.poster = await this.loadRecindex(recindex);
            } catch {
              console.warn(`Failed to load media ${mediarecindex}`);
            }
          }
          for (const a3 of doc.querySelectorAll("[filepos]")) {
            const filepos = a3.getAttribute("filepos");
            a3.href = `filepos:${filepos}`;
          }
        }
        async loadText(section) {
          if (this.#textCache.has(section)) return this.#textCache.get(section);
          const { raw } = section;
          const fileposList = this.#fileposList.filter(({ number }) => number >= section.start && number < section.end).map((obj) => ({ ...obj, offset: obj.number - section.start }));
          let arr = raw;
          if (fileposList.length) {
            arr = raw.subarray(0, fileposList[0].offset);
            fileposList.forEach(({ filepos, offset }, i3) => {
              const next = fileposList[i3 + 1];
              const a3 = this.mobi.encode(`<a id="filepos${filepos}"></a>`);
              arr = concatTypedArray3(arr, a3, raw.subarray(offset, next?.offset));
            });
          }
          const str = this.mobi.decode(arr).replaceAll(mbpPagebreakRegex, "");
          this.#textCache.set(section, str);
          return str;
        }
        async createDocument(section) {
          const str = await this.loadText(section);
          return this.parser.parseFromString(str, this.#type);
        }
        async loadSection(section) {
          if (this.#cache.has(section)) return this.#cache.get(section);
          const doc = await this.createDocument(section);
          const style = doc.createElement("style");
          doc.head.append(style);
          style.append(doc.createTextNode(`blockquote {
            margin-block-start: 0;
            margin-block-end: 0;
            margin-inline-start: 1em;
            margin-inline-end: 0;
        }`));
          await this.replaceResources(doc);
          const result = this.serializer.serializeToString(doc);
          const url = URL.createObjectURL(new Blob([result], { type: this.#type }));
          this.#cache.set(section, url);
          return url;
        }
        resolveHref(href) {
          const filepos = href.match(/filepos:(.*)/)[1];
          const number = Number(filepos);
          const index = this.#sections.findIndex((section) => section.end > number);
          const anchor = (doc) => doc.getElementById(`filepos${filepos}`);
          return { index, anchor };
        }
        splitTOCHref(href) {
          const filepos = href.match(/filepos:(.*)/)[1];
          const number = Number(filepos);
          const index = this.#sections.findIndex((section) => section.end > number);
          return [index, `filepos${filepos}`];
        }
        getTOCFragment(doc, id) {
          return doc.getElementById(id);
        }
        isExternal(uri) {
          return /^(?!blob|filepos)\w+:/i.test(uri);
        }
        destroy() {
          for (const url of this.#resourceCache.values()) URL.revokeObjectURL(url);
          for (const url of this.#cache.values()) URL.revokeObjectURL(url);
        }
      };
      kindleResourceRegex = /kindle:(flow|embed):(\w+)(?:\?mime=(\w+\/[-+.\w]+))?/;
      kindlePosRegex = /kindle:pos:fid:(\w+):off:(\w+)/;
      parseResourceURI = (str) => {
        const [resourceType, id, type] = str.match(kindleResourceRegex).slice(1);
        return { resourceType, id: parseInt(id, 32), type };
      };
      parsePosURI = (str) => {
        const [fid, off] = str.match(kindlePosRegex).slice(1);
        return { fid: parseInt(fid, 32), off: parseInt(off, 32) };
      };
      makePosURI = (fid = 0, off = 0) => `kindle:pos:fid:${fid.toString(32).toUpperCase().padStart(4, "0")}:off:${off.toString(32).toUpperCase().padStart(10, "0")}`;
      getFragmentSelector = (str) => {
        const match = str.match(/\s(id|name|aid)\s*=\s*['"]([^'"]*)['"]/i);
        if (!match) return;
        const [, attr, value] = match;
        return `[${attr}="${CSS.escape(value)}"]`;
      };
      replaceSeries2 = async (str, regex, f3) => {
        const matches = [];
        str.replace(regex, (...args) => (matches.push(args), null));
        const results = [];
        for (const args of matches) results.push(await f3(...args));
        return str.replace(regex, () => results.shift());
      };
      getPageSpread2 = (properties) => {
        for (const p3 of properties) {
          if (p3 === "page-spread-left" || p3 === "rendition:page-spread-left")
            return "left";
          if (p3 === "page-spread-right" || p3 === "rendition:page-spread-right")
            return "right";
          if (p3 === "rendition:page-spread-center") return "center";
        }
      };
      KF8 = class {
        parser = new DOMParser();
        serializer = new XMLSerializer();
        transformTarget = new EventTarget();
        #cache = /* @__PURE__ */ new Map();
        #fragmentOffsets = /* @__PURE__ */ new Map();
        #fragmentSelectors = /* @__PURE__ */ new Map();
        #tables = {};
        #sections;
        #fullRawLength;
        #rawHead = new Uint8Array();
        #rawTail = new Uint8Array();
        #lastLoadedHead = -1;
        #lastLoadedTail = -1;
        #type = MIME2.XHTML;
        #inlineMap = /* @__PURE__ */ new Map();
        constructor(mobi) {
          this.mobi = mobi;
        }
        async init() {
          const loadRecord = this.mobi.loadRecord.bind(this.mobi);
          const { kf8 } = this.mobi.headers;
          try {
            const fdstBuffer = await loadRecord(kf8.fdst);
            const fdst = getStruct(FDST_HEADER, fdstBuffer);
            if (fdst.magic !== "FDST") throw new Error("Missing FDST record");
            const fdstTable = Array.from(
              { length: fdst.numEntries },
              (_2, i3) => 12 + i3 * 8
            ).map((offset) => [
              getUint(fdstBuffer.slice(offset, offset + 4)),
              getUint(fdstBuffer.slice(offset + 4, offset + 8))
            ]);
            this.#tables.fdstTable = fdstTable;
            this.#fullRawLength = fdstTable[fdstTable.length - 1][1];
          } catch {
          }
          const skelTable = (await getIndexData(kf8.skel, loadRecord)).table.map(({ name, tagMap }, index) => ({
            index,
            name,
            numFrag: tagMap[1][0],
            offset: tagMap[6][0],
            length: tagMap[6][1]
          }));
          const fragData = await getIndexData(kf8.frag, loadRecord);
          const fragTable = fragData.table.map(({ name, tagMap }) => ({
            insertOffset: parseInt(name),
            selector: fragData.cncx[tagMap[2][0]],
            index: tagMap[4][0],
            offset: tagMap[6][0],
            length: tagMap[6][1]
          }));
          this.#tables.skelTable = skelTable;
          this.#tables.fragTable = fragTable;
          this.#sections = skelTable.reduce((arr, skel) => {
            const last = arr[arr.length - 1];
            const fragStart = last?.fragEnd ?? 0, fragEnd = fragStart + skel.numFrag;
            const frags = fragTable.slice(fragStart, fragEnd);
            const length = skel.length + frags.map((f3) => f3.length).reduce((a3, b3) => a3 + b3, 0);
            const totalLength = (last?.totalLength ?? 0) + length;
            return arr.concat({ skel, frags, fragEnd, length, totalLength });
          }, []);
          const resources = await this.getResourcesByMagic(["RESC", "PAGE"]);
          const pageSpreads = /* @__PURE__ */ new Map();
          if (resources.RESC) {
            const buf = await this.mobi.loadRecord(resources.RESC);
            const str = this.mobi.decode(buf.slice(16)).replace(/\0/g, "");
            const index = str.search(/\?>/);
            const xmlStr = `<package>${str.slice(index)}</package>`;
            const opf = this.parser.parseFromString(xmlStr, MIME2.XML);
            for (const $itemref of opf.querySelectorAll("spine > itemref")) {
              const i3 = parseInt($itemref.getAttribute("skelid"));
              pageSpreads.set(i3, getPageSpread2(
                $itemref.getAttribute("properties")?.split(" ") ?? []
              ));
            }
          }
          this.sections = this.#sections.map((section, index) => section.frags.length ? {
            id: index,
            load: () => this.loadSection(section),
            createDocument: () => this.createDocument(section),
            size: section.length,
            pageSpread: pageSpreads.get(index)
          } : { linear: "no" });
          try {
            const ncx = await this.mobi.getNCX();
            const map = ({ label, pos, children }) => {
              const [fid, off] = pos;
              const href = makePosURI(fid, off);
              const arr = this.#fragmentOffsets.get(fid);
              if (arr) arr.push(off);
              else this.#fragmentOffsets.set(fid, [off]);
              return { label: unescapeHTML(label), href, subitems: children?.map(map) };
            };
            this.toc = ncx?.map(map);
            this.landmarks = await this.getGuide();
          } catch (e3) {
            console.warn(e3);
          }
          const { exth } = this.mobi.headers;
          this.dir = exth.pageProgressionDirection;
          this.rendition = {
            layout: exth.fixedLayout === "true" ? "pre-paginated" : "reflowable",
            viewport: Object.fromEntries(exth.originalResolution?.split("x")?.slice(0, 2)?.map((x3, i3) => [i3 ? "height" : "width", x3]) ?? [])
          };
          this.metadata = this.mobi.getMetadata();
          this.getCover = this.mobi.getCover.bind(this.mobi);
          return this;
        }
        // is this really the only way of getting to RESC, PAGE, etc.?
        async getResourcesByMagic(keys) {
          const results = {};
          const start = this.mobi.headers.kf8.resourceStart;
          const end = this.mobi.pdb.numRecords;
          for (let i3 = start; i3 < end; i3++) {
            try {
              const magic = await this.mobi.loadMagic(i3);
              const match = keys.find((key) => key === magic);
              if (match) results[match] = i3;
            } catch {
            }
          }
          return results;
        }
        async getGuide() {
          const index = this.mobi.headers.kf8.guide;
          if (index < 4294967295) {
            const loadRecord = this.mobi.loadRecord.bind(this.mobi);
            const { table, cncx } = await getIndexData(index, loadRecord);
            return table.map(({ name, tagMap }) => ({
              label: cncx[tagMap[1][0]] ?? "",
              type: name?.split(/\s/),
              href: makePosURI(tagMap[6]?.[0] ?? tagMap[3]?.[0])
            }));
          }
        }
        async loadResourceBlob(str) {
          const { resourceType, id, type } = parseResourceURI(str);
          const raw = resourceType === "flow" ? await this.loadFlow(id) : await this.mobi.loadResource(id - 1);
          const result = [MIME2.XHTML, MIME2.HTML, MIME2.CSS, MIME2.SVG].includes(type) ? await this.replaceResources(this.mobi.decode(raw)) : raw;
          const detail = { data: result, type };
          const event = new CustomEvent("data", { detail });
          this.transformTarget.dispatchEvent(event);
          const newData = await event.detail.data;
          const newType = await event.detail.type;
          const doc = newType === MIME2.SVG ? this.parser.parseFromString(newData, newType) : null;
          return [
            new Blob([newData], { newType }),
            // SVG wrappers need to be inlined
            // as browsers don't allow external resources when loading SVG as an image
            doc?.getElementsByTagNameNS("http://www.w3.org/2000/svg", "image")?.length ? doc.documentElement : null
          ];
        }
        async loadResource(str) {
          if (this.#cache.has(str)) return this.#cache.get(str);
          const [blob, inline] = await this.loadResourceBlob(str);
          const url = inline ? str : URL.createObjectURL(blob);
          if (inline) this.#inlineMap.set(url, inline);
          this.#cache.set(str, url);
          return url;
        }
        replaceResources(str) {
          const regex = new RegExp(kindleResourceRegex, "g");
          return replaceSeries2(str, regex, this.loadResource.bind(this));
        }
        // NOTE: there doesn't seem to be a way to access text randomly?
        // how to know the decompressed size of the records without decompressing?
        // 4096 is just the maximum size
        async loadRaw(start, end) {
          const distanceHead = end - this.#rawHead.length;
          const distanceEnd = this.#fullRawLength == null ? Infinity : this.#fullRawLength - this.#rawTail.length - start;
          if (distanceHead < 0 || distanceHead < distanceEnd) {
            while (this.#rawHead.length < end) {
              const index = ++this.#lastLoadedHead;
              const data = await this.mobi.loadText(index);
              this.#rawHead = concatTypedArray(this.#rawHead, data);
            }
            return this.#rawHead.slice(start, end);
          }
          while (this.#fullRawLength - this.#rawTail.length > start) {
            const index = this.mobi.headers.palmdoc.numTextRecords - 1 - ++this.#lastLoadedTail;
            const data = await this.mobi.loadText(index);
            this.#rawTail = concatTypedArray(data, this.#rawTail);
          }
          const rawTailStart = this.#fullRawLength - this.#rawTail.length;
          return this.#rawTail.slice(start - rawTailStart, end - rawTailStart);
        }
        loadFlow(index) {
          if (index < 4294967295)
            return this.loadRaw(...this.#tables.fdstTable[index]);
        }
        async loadText(section) {
          const { skel, frags, length } = section;
          const raw = await this.loadRaw(skel.offset, skel.offset + length);
          let skeleton = raw.slice(0, skel.length);
          for (const frag of frags) {
            const insertOffset = frag.insertOffset - skel.offset;
            const offset = skel.length + frag.offset;
            const fragRaw = raw.slice(offset, offset + frag.length);
            skeleton = concatTypedArray3(
              skeleton.slice(0, insertOffset),
              fragRaw,
              skeleton.slice(insertOffset)
            );
            const offsets = this.#fragmentOffsets.get(frag.index);
            if (offsets) for (const offset2 of offsets) {
              const str = this.mobi.decode(fragRaw.slice(offset2));
              const selector = getFragmentSelector(str);
              this.#setFragmentSelector(frag.index, offset2, selector);
            }
          }
          return this.mobi.decode(skeleton);
        }
        async createDocument(section) {
          const str = await this.loadText(section);
          return this.parser.parseFromString(str, this.#type);
        }
        async loadSection(section) {
          if (this.#cache.has(section)) return this.#cache.get(section);
          const str = await this.loadText(section);
          const replaced = await this.replaceResources(str);
          let doc = this.parser.parseFromString(replaced, this.#type);
          if (doc.querySelector("parsererror") || !doc.documentElement?.namespaceURI) {
            this.#type = MIME2.HTML;
            doc = this.parser.parseFromString(replaced, this.#type);
          }
          for (const [url2, node] of this.#inlineMap) {
            for (const el of doc.querySelectorAll(`img[src="${url2}"]`))
              el.replaceWith(node);
          }
          const url = URL.createObjectURL(
            new Blob([this.serializer.serializeToString(doc)], { type: this.#type })
          );
          this.#cache.set(section, url);
          return url;
        }
        getIndexByFID(fid) {
          return this.#sections.findIndex((section) => section.frags.some((frag) => frag.index === fid));
        }
        #setFragmentSelector(id, offset, selector) {
          const map = this.#fragmentSelectors.get(id);
          if (map) map.set(offset, selector);
          else {
            const map2 = /* @__PURE__ */ new Map();
            this.#fragmentSelectors.set(id, map2);
            map2.set(offset, selector);
          }
        }
        async resolveHref(href) {
          const { fid, off } = parsePosURI(href);
          const index = this.getIndexByFID(fid);
          if (index < 0) return;
          const saved = this.#fragmentSelectors.get(fid)?.get(off);
          if (saved) return { index, anchor: (doc) => doc.querySelector(saved) };
          const { skel, frags } = this.#sections[index];
          const frag = frags.find((frag2) => frag2.index === fid);
          const offset = skel.offset + skel.length + frag.offset;
          const fragRaw = await this.loadRaw(offset, offset + frag.length);
          const str = this.mobi.decode(fragRaw.slice(off));
          const selector = getFragmentSelector(str);
          this.#setFragmentSelector(fid, off, selector);
          const anchor = (doc) => doc.querySelector(selector);
          return { index, anchor };
        }
        splitTOCHref(href) {
          const pos = parsePosURI(href);
          const index = this.getIndexByFID(pos.fid);
          return [index, pos];
        }
        getTOCFragment(doc, { fid, off }) {
          const selector = this.#fragmentSelectors.get(fid)?.get(off);
          return doc.querySelector(selector);
        }
        isExternal(uri) {
          return /^(?!blob|kindle)\w+:/i.test(uri);
        }
        destroy() {
          for (const url of this.#cache.values()) URL.revokeObjectURL(url);
        }
      };
    }
  });

  // vendor/fflate.js
  var fflate_exports = {};
  __export(fflate_exports, {
    unzlibSync: () => U2
  });
  function U2(r3, n3) {
    return z2(r3.subarray((a3 = r3, e3 = n3 && n3.dictionary, (8 != (15 & a3[0]) || a3[0] >> 4 > 7 || (a3[0] << 8 | a3[1]) % 31) && E2(6, "invalid zlib data"), (a3[1] >> 5 & 1) == +!e3 && E2(6, "invalid zlib data: " + (32 & a3[1] ? "need" : "unexpected") + " dictionary"), 2 + (a3[1] >> 3 & 4)), -4), { i: 2 }, n3 && n3.out, n3 && n3.dictionary);
    var a3, e3;
  }
  var r2, n2, a2, e2, i2, t2, f2, o2, v2, l2, w2, u2, c2, d2, b2, s2, h2, y2, g2, p2, k2, m2, x2, T2, E2, z2, A2, D2;
  var init_fflate = __esm({
    "vendor/fflate.js"() {
      r2 = Uint8Array;
      n2 = Uint16Array;
      a2 = Int32Array;
      e2 = new r2([0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0, 0, 0, 0]);
      i2 = new r2([0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 0, 0]);
      t2 = new r2([16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]);
      f2 = function(r3, e3) {
        for (var i3 = new n2(31), t3 = 0; t3 < 31; ++t3) i3[t3] = e3 += 1 << r3[t3 - 1];
        var f3 = new a2(i3[30]);
        for (t3 = 1; t3 < 30; ++t3) for (var o3 = i3[t3]; o3 < i3[t3 + 1]; ++o3) f3[o3] = o3 - i3[t3] << 5 | t3;
        return { b: i3, r: f3 };
      };
      o2 = f2(e2, 2);
      v2 = o2.b;
      l2 = o2.r;
      v2[28] = 258, l2[258] = 28;
      for (u2 = f2(i2, 0).b, c2 = new n2(32768), d2 = 0; d2 < 32768; ++d2) {
        w2 = (43690 & d2) >> 1 | (21845 & d2) << 1;
        w2 = (61680 & (w2 = (52428 & w2) >> 2 | (13107 & w2) << 2)) >> 4 | (3855 & w2) << 4, c2[d2] = ((65280 & w2) >> 8 | (255 & w2) << 8) >> 1;
      }
      b2 = function(r3, a3, e3) {
        for (var i3 = r3.length, t3 = 0, f3 = new n2(a3); t3 < i3; ++t3) r3[t3] && ++f3[r3[t3] - 1];
        var o3, v3 = new n2(a3);
        for (t3 = 1; t3 < a3; ++t3) v3[t3] = v3[t3 - 1] + f3[t3 - 1] << 1;
        if (e3) {
          o3 = new n2(1 << a3);
          var l3 = 15 - a3;
          for (t3 = 0; t3 < i3; ++t3) if (r3[t3]) for (var u2 = t3 << 4 | r3[t3], d2 = a3 - r3[t3], w2 = v3[r3[t3] - 1]++ << d2, b3 = w2 | (1 << d2) - 1; w2 <= b3; ++w2) o3[c2[w2] >> l3] = u2;
        } else for (o3 = new n2(i3), t3 = 0; t3 < i3; ++t3) r3[t3] && (o3[t3] = c2[v3[r3[t3] - 1]++] >> 15 - r3[t3]);
        return o3;
      };
      s2 = new r2(288);
      for (d2 = 0; d2 < 144; ++d2) s2[d2] = 8;
      for (d2 = 144; d2 < 256; ++d2) s2[d2] = 9;
      for (d2 = 256; d2 < 280; ++d2) s2[d2] = 7;
      for (d2 = 280; d2 < 288; ++d2) s2[d2] = 8;
      h2 = new r2(32);
      for (d2 = 0; d2 < 32; ++d2) h2[d2] = 5;
      y2 = b2(s2, 9, 1);
      g2 = b2(h2, 5, 1);
      p2 = function(r3) {
        for (var n3 = r3[0], a3 = 1; a3 < r3.length; ++a3) r3[a3] > n3 && (n3 = r3[a3]);
        return n3;
      };
      k2 = function(r3, n3, a3) {
        var e3 = n3 / 8 | 0;
        return (r3[e3] | r3[e3 + 1] << 8) >> (7 & n3) & a3;
      };
      m2 = function(r3, n3) {
        var a3 = n3 / 8 | 0;
        return (r3[a3] | r3[a3 + 1] << 8 | r3[a3 + 2] << 16) >> (7 & n3);
      };
      x2 = function(r3) {
        return (r3 + 7) / 8 | 0;
      };
      T2 = ["unexpected EOF", "invalid block type", "invalid length/literal", "invalid distance", "stream finished", "no stream handler", , "no callback", "invalid UTF-8 data", "extra field too long", "date not in range 1980-2099", "filename too long", "stream finishing", "invalid zip data"];
      E2 = function(r3, n3, a3) {
        var e3 = new Error(n3 || T2[r3]);
        if (e3.code = r3, Error.captureStackTrace && Error.captureStackTrace(e3, E2), !a3) throw e3;
        return e3;
      };
      z2 = function(n3, a3, f3, o3) {
        var l3 = n3.length, c2 = o3 ? o3.length : 0;
        if (!l3 || a3.f && !a3.l) return f3 || new r2(0);
        var d2 = !f3, w2 = d2 || 2 != a3.i, s3 = a3.i;
        d2 && (f3 = new r2(3 * l3));
        var h3 = function(n4) {
          var a4 = f3.length;
          if (n4 > a4) {
            var e3 = new r2(Math.max(2 * a4, n4));
            e3.set(f3), f3 = e3;
          }
        }, T3 = a3.f || 0, z3 = a3.p || 0, A3 = a3.b || 0, U3 = a3.l, D3 = a3.d, F2 = a3.m, M2 = a3.n, S2 = 8 * l3;
        do {
          if (!U3) {
            T3 = k2(n3, z3, 1);
            var I2 = k2(n3, z3 + 1, 3);
            if (z3 += 3, !I2) {
              var O2 = n3[(P2 = x2(z3) + 4) - 4] | n3[P2 - 3] << 8, j2 = P2 + O2;
              if (j2 > l3) {
                s3 && E2(0);
                break;
              }
              w2 && h3(A3 + O2), f3.set(n3.subarray(P2, j2), A3), a3.b = A3 += O2, a3.p = z3 = 8 * j2, a3.f = T3;
              continue;
            }
            if (1 == I2) U3 = y2, D3 = g2, F2 = 9, M2 = 5;
            else if (2 == I2) {
              var q2 = k2(n3, z3, 31) + 257, B2 = k2(n3, z3 + 10, 15) + 4, C2 = q2 + k2(n3, z3 + 5, 31) + 1;
              z3 += 14;
              for (var G2 = new r2(C2), H2 = new r2(19), J2 = 0; J2 < B2; ++J2) H2[t2[J2]] = k2(n3, z3 + 3 * J2, 7);
              z3 += 3 * B2;
              var K2 = p2(H2), L2 = (1 << K2) - 1, N2 = b2(H2, K2, 1);
              for (J2 = 0; J2 < C2; ) {
                var P2, Q2 = N2[k2(n3, z3, L2)];
                if (z3 += 15 & Q2, (P2 = Q2 >> 4) < 16) G2[J2++] = P2;
                else {
                  var R2 = 0, V2 = 0;
                  for (16 == P2 ? (V2 = 3 + k2(n3, z3, 3), z3 += 2, R2 = G2[J2 - 1]) : 17 == P2 ? (V2 = 3 + k2(n3, z3, 7), z3 += 3) : 18 == P2 && (V2 = 11 + k2(n3, z3, 127), z3 += 7); V2--; ) G2[J2++] = R2;
                }
              }
              var W2 = G2.subarray(0, q2), X2 = G2.subarray(q2);
              F2 = p2(W2), M2 = p2(X2), U3 = b2(W2, F2, 1), D3 = b2(X2, M2, 1);
            } else E2(1);
            if (z3 > S2) {
              s3 && E2(0);
              break;
            }
          }
          w2 && h3(A3 + 131072);
          for (var Y2 = (1 << F2) - 1, Z2 = (1 << M2) - 1, $2 = z3; ; $2 = z3) {
            var _2 = (R2 = U3[m2(n3, z3) & Y2]) >> 4;
            if ((z3 += 15 & R2) > S2) {
              s3 && E2(0);
              break;
            }
            if (R2 || E2(2), _2 < 256) f3[A3++] = _2;
            else {
              if (256 == _2) {
                $2 = z3, U3 = null;
                break;
              }
              var rr = _2 - 254;
              if (_2 > 264) {
                var nr = e2[J2 = _2 - 257];
                rr = k2(n3, z3, (1 << nr) - 1) + v2[J2], z3 += nr;
              }
              var ar = D3[m2(n3, z3) & Z2], er = ar >> 4;
              ar || E2(3), z3 += 15 & ar;
              X2 = u2[er];
              if (er > 3) {
                nr = i2[er];
                X2 += m2(n3, z3) & (1 << nr) - 1, z3 += nr;
              }
              if (z3 > S2) {
                s3 && E2(0);
                break;
              }
              w2 && h3(A3 + 131072);
              var ir = A3 + rr;
              if (A3 < X2) {
                var tr = c2 - X2, fr = Math.min(X2, ir);
                for (tr + A3 < 0 && E2(3); A3 < fr; ++A3) f3[A3] = o3[tr + A3];
              }
              for (; A3 < ir; ++A3) f3[A3] = f3[A3 - X2];
            }
          }
          a3.l = U3, a3.p = $2, a3.b = A3, a3.f = T3, U3 && (T3 = 1, a3.m = F2, a3.d = D3, a3.n = M2);
        } while (!T3);
        return A3 != f3.length && d2 ? (function(n4, a4, e3) {
          return (null == e3 || e3 > n4.length) && (e3 = n4.length), new r2(n4.subarray(a4, e3));
        })(f3, 0, A3) : f3.subarray(0, A3);
      };
      A2 = new r2(0);
      D2 = "undefined" != typeof TextDecoder && new TextDecoder();
      try {
        D2.decode(A2, { stream: true });
      } catch (r3) {
      }
    }
  });

  // fixed-layout.js
  var fixed_layout_exports = {};
  __export(fixed_layout_exports, {
    FixedLayout: () => FixedLayout
  });
  var parseViewport, getViewport, FixedLayout;
  var init_fixed_layout = __esm({
    "fixed-layout.js"() {
      parseViewport = (str) => str?.split(/[,;\s]/)?.filter((x3) => x3)?.map((x3) => x3.split("=").map((x4) => x4.trim()));
      getViewport = (doc, viewport) => {
        if (doc.documentElement.localName === "svg") {
          const [, , width, height] = doc.documentElement.getAttribute("viewBox")?.split(/\s/) ?? [];
          return { width, height };
        }
        const meta = parseViewport(doc.querySelector('meta[name="viewport"]')?.getAttribute("content"));
        if (meta) return Object.fromEntries(meta);
        if (typeof viewport === "string") return parseViewport(viewport);
        if (viewport?.width && viewport.height) return viewport;
        const img = doc.querySelector("img");
        if (img) return { width: img.naturalWidth, height: img.naturalHeight };
        console.warn(new Error("Missing viewport properties"));
        return { width: 1e3, height: 2e3 };
      };
      FixedLayout = class extends HTMLElement {
        static observedAttributes = ["zoom"];
        #root = this.attachShadow({ mode: "closed" });
        #observer = new ResizeObserver(() => this.#render());
        #spreads;
        #index = -1;
        defaultViewport;
        spread;
        #portrait = false;
        #left;
        #right;
        #center;
        #side;
        #zoom;
        constructor() {
          super();
          const sheet = new CSSStyleSheet();
          this.#root.adoptedStyleSheets = [sheet];
          sheet.replaceSync(`:host {
            width: 100%;
            height: 100%;
            display: flex;
            justify-content: center;
            align-items: center;
            overflow: auto;
        }`);
          this.#observer.observe(this);
        }
        attributeChangedCallback(name, _2, value) {
          switch (name) {
            case "zoom":
              this.#zoom = value !== "fit-width" && value !== "fit-page" ? parseFloat(value) : value;
              this.#render();
              break;
          }
        }
        async #createFrame({ index, src: srcOption }) {
          const srcOptionIsString = typeof srcOption === "string";
          const src = srcOptionIsString ? srcOption : srcOption?.src;
          const onZoom = srcOptionIsString ? null : srcOption?.onZoom;
          const element = document.createElement("div");
          element.setAttribute("dir", "ltr");
          const iframe = document.createElement("iframe");
          element.append(iframe);
          Object.assign(iframe.style, {
            border: "0",
            display: "none",
            overflow: "hidden"
          });
          iframe.setAttribute("sandbox", "allow-same-origin allow-scripts");
          iframe.setAttribute("scrolling", "no");
          iframe.setAttribute("part", "filter");
          this.#root.append(element);
          if (!src) return { blank: true, element, iframe };
          return new Promise((resolve) => {
            iframe.addEventListener("load", () => {
              const doc = iframe.contentDocument;
              this.dispatchEvent(new CustomEvent("load", { detail: { doc, index } }));
              const { width, height } = getViewport(doc, this.defaultViewport);
              resolve({
                element,
                iframe,
                width: parseFloat(width),
                height: parseFloat(height),
                onZoom
              });
            }, { once: true });
            iframe.src = src;
          });
        }
        #render(side = this.#side) {
          if (!side) return;
          const left = this.#left ?? {};
          const right = this.#center ?? this.#right ?? {};
          const target = side === "left" ? left : right;
          const { width, height } = this.getBoundingClientRect();
          const portrait = this.spread !== "both" && this.spread !== "portrait" && height > width;
          this.#portrait = portrait;
          const blankWidth = left.width ?? right.width ?? 0;
          const blankHeight = left.height ?? right.height ?? 0;
          const scale = typeof this.#zoom === "number" && !isNaN(this.#zoom) ? this.#zoom : (this.#zoom === "fit-width" ? portrait || this.#center ? width / (target.width ?? blankWidth) : width / ((left.width ?? blankWidth) + (right.width ?? blankWidth)) : portrait || this.#center ? Math.min(
            width / (target.width ?? blankWidth),
            height / (target.height ?? blankHeight)
          ) : Math.min(
            width / ((left.width ?? blankWidth) + (right.width ?? blankWidth)),
            height / Math.max(
              left.height ?? blankHeight,
              right.height ?? blankHeight
            )
          )) || 1;
          const transform = (frame) => {
            let { element, iframe, width: width2, height: height2, blank, onZoom } = frame;
            if (!iframe) return;
            if (onZoom) onZoom({ doc: frame.iframe.contentDocument, scale });
            const iframeScale = onZoom ? scale : 1;
            Object.assign(iframe.style, {
              width: `${width2 * iframeScale}px`,
              height: `${height2 * iframeScale}px`,
              transform: onZoom ? "none" : `scale(${scale})`,
              transformOrigin: "top left",
              display: blank ? "none" : "block"
            });
            Object.assign(element.style, {
              width: `${(width2 ?? blankWidth) * scale}px`,
              height: `${(height2 ?? blankHeight) * scale}px`,
              overflow: "hidden",
              display: "block",
              flexShrink: "0",
              marginBlock: "auto"
            });
            if (portrait && frame !== target) {
              element.style.display = "none";
            }
          };
          if (this.#center) {
            transform(this.#center);
          } else {
            transform(left);
            transform(right);
          }
        }
        async #showSpread({ left, right, center, side }) {
          this.#root.replaceChildren();
          this.#left = null;
          this.#right = null;
          this.#center = null;
          if (center) {
            this.#center = await this.#createFrame(center);
            this.#side = "center";
            this.#render();
          } else {
            this.#left = await this.#createFrame(left);
            this.#right = await this.#createFrame(right);
            this.#side = this.#left.blank ? "right" : this.#right.blank ? "left" : side;
            this.#render();
          }
        }
        #goLeft() {
          if (this.#center || this.#left?.blank) return;
          if (this.#portrait && this.#left?.element?.style?.display === "none") {
            this.#side = "left";
            this.#render();
            this.#reportLocation("page");
            return true;
          }
        }
        #goRight() {
          if (this.#center || this.#right?.blank) return;
          if (this.#portrait && this.#right?.element?.style?.display === "none") {
            this.#side = "right";
            this.#render();
            this.#reportLocation("page");
            return true;
          }
        }
        open(book) {
          this.book = book;
          const { rendition } = book;
          this.spread = rendition?.spread;
          this.defaultViewport = rendition?.viewport;
          const rtl = book.dir === "rtl";
          const ltr = !rtl;
          this.rtl = rtl;
          if (rendition?.spread === "none")
            this.#spreads = book.sections.map((section) => ({ center: section }));
          else this.#spreads = book.sections.reduce((arr, section, i3) => {
            const last = arr[arr.length - 1];
            const { pageSpread } = section;
            const newSpread = () => {
              const spread = {};
              arr.push(spread);
              return spread;
            };
            if (pageSpread === "center") {
              const spread = last.left || last.right ? newSpread() : last;
              spread.center = section;
            } else if (pageSpread === "left") {
              const spread = last.center || last.left || ltr && i3 ? newSpread() : last;
              spread.left = section;
            } else if (pageSpread === "right") {
              const spread = last.center || last.right || rtl && i3 ? newSpread() : last;
              spread.right = section;
            } else if (ltr) {
              if (last.center || last.right) newSpread().left = section;
              else if (last.left || !i3) last.right = section;
              else last.left = section;
            } else {
              if (last.center || last.left) newSpread().right = section;
              else if (last.right || !i3) last.left = section;
              else last.right = section;
            }
            return arr;
          }, [{}]);
        }
        get index() {
          const spread = this.#spreads[this.#index];
          const section = spread?.center ?? (this.#side === "left" ? spread.left ?? spread.right : spread.right ?? spread.left);
          return this.book.sections.indexOf(section);
        }
        #reportLocation(reason) {
          this.dispatchEvent(new CustomEvent("relocate", { detail: { reason, range: null, index: this.index, fraction: 0, size: 1 } }));
        }
        getSpreadOf(section) {
          const spreads = this.#spreads;
          for (let index = 0; index < spreads.length; index++) {
            const { left, right, center } = spreads[index];
            if (left === section) return { index, side: "left" };
            if (right === section) return { index, side: "right" };
            if (center === section) return { index, side: "center" };
          }
        }
        async goToSpread(index, side, reason) {
          if (index < 0 || index > this.#spreads.length - 1) return;
          if (index === this.#index) {
            this.#render(side);
            return;
          }
          this.#index = index;
          const spread = this.#spreads[index];
          if (spread.center) {
            const index2 = this.book.sections.indexOf(spread.center);
            const src = await spread.center?.load?.();
            await this.#showSpread({ center: { index: index2, src } });
          } else {
            const indexL = this.book.sections.indexOf(spread.left);
            const indexR = this.book.sections.indexOf(spread.right);
            const srcL = await spread.left?.load?.();
            const srcR = await spread.right?.load?.();
            const left = { index: indexL, src: srcL };
            const right = { index: indexR, src: srcR };
            await this.#showSpread({ left, right, side });
          }
          this.#reportLocation(reason);
        }
        async select(target) {
          await this.goTo(target);
        }
        async goTo(target) {
          const { book } = this;
          const resolved = await target;
          const section = book.sections[resolved.index];
          if (!section) return;
          const { index, side } = this.getSpreadOf(section);
          await this.goToSpread(index, side);
        }
        async next() {
          const s3 = this.rtl ? this.#goLeft() : this.#goRight();
          if (!s3) return this.goToSpread(this.#index + 1, this.rtl ? "right" : "left", "page");
        }
        async prev() {
          const s3 = this.rtl ? this.#goRight() : this.#goLeft();
          if (!s3) return this.goToSpread(this.#index - 1, this.rtl ? "left" : "right", "page");
        }
        getContents() {
          return Array.from(this.#root.querySelectorAll("iframe"), (frame) => ({
            doc: frame.contentDocument
            // TODO: index, overlayer
          }));
        }
        destroy() {
          this.#observer.unobserve(this);
        }
      };
      customElements.define("foliate-fxl", FixedLayout);
    }
  });

  // paginator.js
  var paginator_exports = {};
  __export(paginator_exports, {
    Paginator: () => Paginator
  });
  var wait, debounce, lerp, easeOutQuad, animate, uncollapse, makeRange, bisectNode, SHOW_ELEMENT, SHOW_TEXT, SHOW_CDATA_SECTION, FILTER_ACCEPT, FILTER_REJECT, FILTER_SKIP, filter2, getBoundingClientRect, getVisibleRange, selectionIsBackward, setSelectionTo, getDirection, scrollModelFor, getBackground, makeMarginals, setStylesImportant, View, Paginator;
  var init_paginator = __esm({
    "paginator.js"() {
      wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
      debounce = (f3, wait2, immediate) => {
        let timeout;
        return (...args) => {
          const later = () => {
            timeout = null;
            if (!immediate) f3(...args);
          };
          const callNow = immediate && !timeout;
          if (timeout) clearTimeout(timeout);
          timeout = setTimeout(later, wait2);
          if (callNow) f3(...args);
        };
      };
      lerp = (min, max, x3) => x3 * (max - min) + min;
      easeOutQuad = (x3) => 1 - (1 - x3) * (1 - x3);
      animate = (a3, b3, duration, ease, render) => new Promise((resolve) => {
        let start;
        const step = (now) => {
          if (document.hidden) {
            render(lerp(a3, b3, 1));
            return resolve();
          }
          start ??= now;
          const fraction = Math.min(1, (now - start) / duration);
          render(lerp(a3, b3, ease(fraction)));
          if (fraction < 1) requestAnimationFrame(step);
          else resolve();
        };
        if (document.hidden) {
          render(lerp(a3, b3, 1));
          return resolve();
        }
        requestAnimationFrame(step);
      });
      uncollapse = (range) => {
        if (!range?.collapsed) return range;
        const { endOffset, endContainer } = range;
        if (endContainer.nodeType === 1) {
          const node = endContainer.childNodes[endOffset];
          if (node?.nodeType === 1) return node;
          return endContainer;
        }
        if (endOffset + 1 < endContainer.length) range.setEnd(endContainer, endOffset + 1);
        else if (endOffset > 1) range.setStart(endContainer, endOffset - 1);
        else return endContainer.parentNode;
        return range;
      };
      makeRange = (doc, node, start, end = start) => {
        const range = doc.createRange();
        range.setStart(node, start);
        range.setEnd(node, end);
        return range;
      };
      bisectNode = (doc, node, cb, start = 0, end = node.nodeValue.length) => {
        if (end - start === 1) {
          const result2 = cb(makeRange(doc, node, start), makeRange(doc, node, end));
          return result2 < 0 ? start : end;
        }
        const mid = Math.floor(start + (end - start) / 2);
        const result = cb(makeRange(doc, node, start, mid), makeRange(doc, node, mid, end));
        return result < 0 ? bisectNode(doc, node, cb, start, mid) : result > 0 ? bisectNode(doc, node, cb, mid, end) : mid;
      };
      ({
        SHOW_ELEMENT,
        SHOW_TEXT,
        SHOW_CDATA_SECTION,
        FILTER_ACCEPT,
        FILTER_REJECT,
        FILTER_SKIP
      } = NodeFilter);
      filter2 = SHOW_ELEMENT | SHOW_TEXT | SHOW_CDATA_SECTION;
      getBoundingClientRect = (target) => {
        let top = Infinity, right = -Infinity, left = Infinity, bottom = -Infinity;
        for (const rect of target.getClientRects()) {
          left = Math.min(left, rect.left);
          top = Math.min(top, rect.top);
          right = Math.max(right, rect.right);
          bottom = Math.max(bottom, rect.bottom);
        }
        return new DOMRect(left, top, right - left, bottom - top);
      };
      getVisibleRange = (doc, start, end, mapRect) => {
        const acceptNode2 = (node) => {
          const name = node.localName?.toLowerCase();
          if (name === "script" || name === "style") return FILTER_REJECT;
          if (node.nodeType === 1) {
            const { left, right } = mapRect(node.getBoundingClientRect());
            if (right < start || left > end) return FILTER_REJECT;
            if (left >= start && right <= end) return FILTER_ACCEPT;
          } else {
            if (!node.nodeValue?.trim()) return FILTER_SKIP;
            const range2 = doc.createRange();
            range2.selectNodeContents(node);
            const { left, right } = mapRect(range2.getBoundingClientRect());
            if (right >= start && left <= end) return FILTER_ACCEPT;
          }
          return FILTER_SKIP;
        };
        const walker = doc.createTreeWalker(doc.body, filter2, { acceptNode: acceptNode2 });
        const nodes = [];
        for (let node = walker.nextNode(); node; node = walker.nextNode())
          nodes.push(node);
        const from = nodes[0] ?? doc.body;
        const to = nodes[nodes.length - 1] ?? from;
        const startOffset = from.nodeType === 1 ? 0 : bisectNode(doc, from, (a3, b3) => {
          const p3 = mapRect(getBoundingClientRect(a3));
          const q2 = mapRect(getBoundingClientRect(b3));
          if (p3.right < start && q2.left > start) return 0;
          return q2.left > start ? -1 : 1;
        });
        const endOffset = to.nodeType === 1 ? 0 : bisectNode(doc, to, (a3, b3) => {
          const p3 = mapRect(getBoundingClientRect(a3));
          const q2 = mapRect(getBoundingClientRect(b3));
          if (p3.right < end && q2.left > end) return 0;
          return q2.left > end ? -1 : 1;
        });
        const range = doc.createRange();
        range.setStart(from, startOffset);
        range.setEnd(to, endOffset);
        return range;
      };
      selectionIsBackward = (sel) => {
        const range = document.createRange();
        range.setStart(sel.anchorNode, sel.anchorOffset);
        range.setEnd(sel.focusNode, sel.focusOffset);
        return range.collapsed;
      };
      setSelectionTo = (target, collapse2) => {
        let range;
        if (target.startContainer) range = target.cloneRange();
        else if (target.nodeType) {
          range = document.createRange();
          range.selectNode(target);
        }
        if (range) {
          const sel = range.startContainer.ownerDocument.defaultView.getSelection();
          if (sel) {
            sel.removeAllRanges();
            if (collapse2 === -1) range.collapse(true);
            else if (collapse2 === 1) range.collapse();
            sel.addRange(range);
          }
        }
      };
      getDirection = (doc) => {
        const { defaultView } = doc;
        const { writingMode, direction } = defaultView.getComputedStyle(doc.body);
        const vertical = writingMode === "vertical-rl" || writingMode === "vertical-lr";
        const rtl = doc.body.dir === "rtl" || direction === "rtl" || doc.documentElement.dir === "rtl";
        return { vertical, rtl, writingMode };
      };
      scrollModelFor = (writingMode) => {
        switch (writingMode) {
          case "vertical-rl":
            return {
              axis: "horizontal",
              scrollProp: "scrollLeft",
              sizeProp: "width",
              rectStartProp: "right",
              directionSign: -1
            };
          case "vertical-lr":
            return {
              axis: "horizontal",
              scrollProp: "scrollLeft",
              sizeProp: "width",
              rectStartProp: "left",
              directionSign: 1
            };
          default:
            return {
              axis: "vertical",
              scrollProp: "scrollTop",
              sizeProp: "height",
              rectStartProp: "top",
              directionSign: 1
            };
        }
      };
      getBackground = (doc) => {
        const bodyStyle = doc.defaultView.getComputedStyle(doc.body);
        return bodyStyle.backgroundColor === "rgba(0, 0, 0, 0)" && bodyStyle.backgroundImage === "none" ? doc.defaultView.getComputedStyle(doc.documentElement).background : bodyStyle.background;
      };
      makeMarginals = (length, part) => Array.from({ length }, () => {
        const div = document.createElement("div");
        const child = document.createElement("div");
        div.append(child);
        child.setAttribute("part", part);
        return div;
      });
      setStylesImportant = (el, styles) => {
        const { style } = el;
        for (const [k3, v3] of Object.entries(styles)) style.setProperty(k3, v3, "important");
      };
      View = class {
        #observer = new ResizeObserver(() => this.expand());
        #element = document.createElement("div");
        #iframe = document.createElement("iframe");
        #contentRange = document.createRange();
        #overlayer;
        #vertical = false;
        #rtl = false;
        // Feature #76 WI-1b: the loaded section's scroll model (axis/props/sign),
        // mirroring Swift `FoliateScrollModel`. Defaults to the horizontal-tb model
        // (Feature #73 vertical-scroll path). Stored additively here; the windowed
        // primitives consume it in WI-3.
        #scrollModel = scrollModelFor("horizontal-tb");
        #column = true;
        #size;
        #layout = {};
        constructor({ container, onExpand }) {
          this.container = container;
          this.onExpand = onExpand;
          this.#iframe.setAttribute("part", "filter");
          this.#element.append(this.#iframe);
          Object.assign(this.#element.style, {
            boxSizing: "content-box",
            position: "relative",
            overflow: "hidden",
            flex: "0 0 auto",
            width: "100%",
            height: "100%",
            display: "flex",
            justifyContent: "center",
            alignItems: "center"
          });
          Object.assign(this.#iframe.style, {
            overflow: "hidden",
            border: "0",
            display: "none",
            width: "100%",
            height: "100%"
          });
          this.#iframe.setAttribute("sandbox", "allow-same-origin allow-scripts");
          this.#iframe.setAttribute("scrolling", "no");
        }
        get element() {
          return this.#element;
        }
        get document() {
          return this.#iframe.contentDocument;
        }
        // Feature #76 WI-1b: the loaded section's scroll model (axis/props/sign).
        // Consumed by the windowed primitives in WI-3.
        get scrollModel() {
          return this.#scrollModel;
        }
        async load(src, afterLoad, beforeRender) {
          if (typeof src !== "string") throw new Error(`${src} is not string`);
          return new Promise((resolve) => {
            this.#iframe.addEventListener("load", () => {
              const doc = this.document;
              afterLoad?.(doc);
              this.#iframe.style.display = "block";
              const { vertical, rtl, writingMode } = getDirection(doc);
              const background = getBackground(doc);
              this.#iframe.style.display = "none";
              this.#vertical = vertical;
              this.#rtl = rtl;
              this.#scrollModel = scrollModelFor(writingMode);
              this.#contentRange.selectNodeContents(doc.body);
              const layout = beforeRender?.({ vertical, rtl, background });
              this.#iframe.style.display = "block";
              this.render(layout);
              this.#observer.observe(doc.body);
              doc.fonts.ready.then(() => this.expand());
              resolve();
            }, { once: true });
            this.#iframe.src = src;
          });
        }
        render(layout) {
          if (!layout) return;
          this.#column = layout.flow !== "scrolled";
          this.#layout = layout;
          if (this.#column) this.columnize(layout);
          else this.scrolled(layout);
        }
        scrolled({ gap, columnWidth }) {
          const vertical = this.#vertical;
          const doc = this.document;
          setStylesImportant(doc.documentElement, {
            "box-sizing": "border-box",
            "padding": vertical ? `${gap}px 0` : `0 ${gap}px`,
            "column-width": "auto",
            "height": "auto",
            "width": "auto"
          });
          setStylesImportant(doc.body, {
            [vertical ? "max-height" : "max-width"]: `${columnWidth}px`,
            "margin": "auto"
          });
          this.setImageSize();
          this.expand();
        }
        columnize({ width, height, gap, columnWidth }) {
          const vertical = this.#vertical;
          this.#size = vertical ? height : width;
          const doc = this.document;
          setStylesImportant(doc.documentElement, {
            "box-sizing": "border-box",
            "column-width": `${Math.trunc(columnWidth)}px`,
            "column-gap": `${gap}px`,
            "column-fill": "auto",
            ...vertical ? { "width": `${width}px` } : { "height": `${height}px` },
            "padding": vertical ? `${gap / 2}px 0` : `0 ${gap / 2}px`,
            "overflow": "hidden",
            // force wrap long words
            "overflow-wrap": "break-word",
            // reset some potentially problematic props
            "position": "static",
            "border": "0",
            "margin": "0",
            "max-height": "none",
            "max-width": "none",
            "min-height": "none",
            "min-width": "none",
            // fix glyph clipping in WebKit
            "-webkit-line-box-contain": "block glyphs replaced"
          });
          setStylesImportant(doc.body, {
            "max-height": "none",
            "max-width": "none",
            "margin": "0"
          });
          this.setImageSize();
          this.expand();
        }
        setImageSize() {
          const { width, height, margin } = this.#layout;
          const vertical = this.#vertical;
          const doc = this.document;
          for (const el of doc.body.querySelectorAll("img, svg, video")) {
            const { maxHeight, maxWidth } = doc.defaultView.getComputedStyle(el);
            setStylesImportant(el, {
              "max-height": vertical ? maxHeight !== "none" && maxHeight !== "0px" ? maxHeight : "100%" : `${height - margin * 2}px`,
              "max-width": vertical ? `${width - margin * 2}px` : maxWidth !== "none" && maxWidth !== "0px" ? maxWidth : "100%",
              "object-fit": "contain",
              "page-break-inside": "avoid",
              "break-inside": "avoid",
              "box-sizing": "border-box"
            });
          }
        }
        expand() {
          const { documentElement } = this.document;
          if (this.#column) {
            const side = this.#vertical ? "height" : "width";
            const otherSide = this.#vertical ? "width" : "height";
            const contentRect = this.#contentRange.getBoundingClientRect();
            const rootRect = documentElement.getBoundingClientRect();
            const contentStart = this.#vertical ? 0 : this.#rtl ? rootRect.right - contentRect.right : contentRect.left - rootRect.left;
            const contentSize = contentStart + contentRect[side];
            const pageCount = Math.ceil(contentSize / this.#size);
            const expandedSize = pageCount * this.#size;
            this.#element.style.padding = "0";
            this.#iframe.style[side] = `${expandedSize}px`;
            this.#element.style[side] = `${expandedSize + this.#size * 2}px`;
            this.#iframe.style[otherSide] = "100%";
            this.#element.style[otherSide] = "100%";
            documentElement.style[side] = `${this.#size}px`;
            if (this.#overlayer) {
              this.#overlayer.element.style.margin = "0";
              this.#overlayer.element.style.left = this.#vertical ? "0" : `${this.#size}px`;
              this.#overlayer.element.style.top = this.#vertical ? `${this.#size}px` : "0";
              this.#overlayer.element.style[side] = `${expandedSize}px`;
              this.#overlayer.redraw();
            }
          } else {
            const side = this.#vertical ? "width" : "height";
            const otherSide = this.#vertical ? "height" : "width";
            const contentSize = documentElement.getBoundingClientRect()[side];
            const expandedSize = contentSize;
            const { margin } = this.#layout;
            const padding = this.#vertical ? `0 ${margin}px` : `${margin}px 0`;
            this.#element.style.padding = padding;
            this.#iframe.style[side] = `${expandedSize}px`;
            this.#element.style[side] = `${expandedSize}px`;
            this.#iframe.style[otherSide] = "100%";
            this.#element.style[otherSide] = "100%";
            if (this.#overlayer) {
              this.#overlayer.element.style.margin = padding;
              this.#overlayer.element.style.left = "0";
              this.#overlayer.element.style.top = "0";
              this.#overlayer.element.style[side] = `${expandedSize}px`;
              this.#overlayer.redraw();
            }
          }
          this.onExpand();
        }
        set overlayer(overlayer) {
          this.#overlayer = overlayer;
          this.#element.append(overlayer.element);
        }
        get overlayer() {
          return this.#overlayer;
        }
        destroy() {
          if (this.document) this.#observer.unobserve(this.document.body);
        }
      };
      Paginator = class extends HTMLElement {
        static observedAttributes = [
          "flow",
          "gap",
          "margin",
          "max-inline-size",
          "max-block-size",
          "max-column-count"
        ];
        #root = this.attachShadow({ mode: "closed" });
        #observer = new ResizeObserver(() => this.render());
        #top;
        #background;
        #container;
        #header;
        #footer;
        #view;
        // Feature #73 WI-1a: scrolled-mode windowed-rendering scaffold. The
        // `#scrolledViews` list holds the mounted window of section views (current
        // + neighbours) when `#windowedScroll` is on. The flag defaults OFF, so
        // every consumer that routes through `#mountedViews()` / `#currentView()`
        // is byte-identical to the single-`#view` path until WI-2 lights it up.
        // Paged mode never touches these (it stays the exact single-`#view` code).
        #scrolledViews = [];
        #mountingIndices = /* @__PURE__ */ new Set();
        // WI-3: in-flight mount dedup (async race guard)
        #windowGeneration = 0;
        // Gate-4 H1: bumped on navigation/teardown; stale mounts abort
        // Feature #73: windowed multi-section continuous scroll for AZW3/MOBI scroll
        // mode — ON by default. Replaces the per-section view-swap (the Bug #283
        // chapter-boundary jump) with a K-window continuous surface. Horizontal-
        // writing scrolled mode only; vertical writing + paged mode fall back to the
        // single-`#view` path. Shipped after a 2-round Codex audit (ship-as-is) +
        // flag-on device verification.
        #windowedScroll = true;
        #K = 3;
        // Feature #73 WI-2: windowed mount size (current + neighbours)
        #vertical = false;
        #rtl = false;
        #margin = 0;
        #index = -1;
        #anchor = 0;
        // anchor view to a fraction (0-1), Range, or Element
        #justAnchored = false;
        #locked = false;
        // while true, prevent any further navigation
        #styles;
        #styleMap = /* @__PURE__ */ new WeakMap();
        #mediaQuery = matchMedia("(prefers-color-scheme: dark)");
        #mediaQueryListener;
        #scrollBounds;
        #touchState;
        #touchScrolled;
        #lastVisibleRange;
        constructor() {
          super();
          this.#root.innerHTML = `<style>
        :host {
            display: block;
            container-type: size;
        }
        :host, #top {
            box-sizing: border-box;
            position: relative;
            overflow: hidden;
            width: 100%;
            height: 100%;
        }
        #top {
            --_gap: 7%;
            --_margin: 48px;
            --_max-inline-size: 720px;
            --_max-block-size: 1440px;
            --_max-column-count: 2;
            --_max-column-count-portrait: 1;
            --_max-column-count-spread: var(--_max-column-count);
            --_half-gap: calc(var(--_gap) / 2);
            --_max-width: calc(var(--_max-inline-size) * var(--_max-column-count-spread));
            --_max-height: var(--_max-block-size);
            display: grid;
            grid-template-columns:
                minmax(var(--_half-gap), 1fr)
                var(--_half-gap)
                minmax(0, calc(var(--_max-width) - var(--_gap)))
                var(--_half-gap)
                minmax(var(--_half-gap), 1fr);
            grid-template-rows:
                minmax(var(--_margin), 1fr)
                minmax(0, var(--_max-height))
                minmax(var(--_margin), 1fr);
            &.vertical {
                --_max-column-count-spread: var(--_max-column-count-portrait);
                --_max-width: var(--_max-block-size);
                --_max-height: calc(var(--_max-inline-size) * var(--_max-column-count-spread));
            }
            @container (orientation: portrait) {
                & {
                    --_max-column-count-spread: var(--_max-column-count-portrait);
                }
                &.vertical {
                    --_max-column-count-spread: var(--_max-column-count);
                }
            }
        }
        #background {
            grid-column: 1 / -1;
            grid-row: 1 / -1;
        }
        #container {
            grid-column: 2 / 5;
            grid-row: 2;
            overflow: hidden;
        }
        :host([flow="scrolled"]) #container {
            grid-column: 1 / -1;
            grid-row: 1 / -1;
            overflow: auto;
        }
        #header {
            grid-column: 3 / 4;
            grid-row: 1;
        }
        #footer {
            grid-column: 3 / 4;
            grid-row: 3;
            align-self: end;
        }
        #header, #footer {
            display: grid;
            height: var(--_margin);
        }
        :is(#header, #footer) > * {
            display: flex;
            align-items: center;
            min-width: 0;
        }
        :is(#header, #footer) > * > * {
            width: 100%;
            overflow: hidden;
            white-space: nowrap;
            text-overflow: ellipsis;
            text-align: center;
            font-size: .75em;
            opacity: .6;
        }
        </style>
        <div id="top">
            <div id="background" part="filter"></div>
            <div id="header"></div>
            <div id="container"></div>
            <div id="footer"></div>
        </div>
        `;
          this.#top = this.#root.getElementById("top");
          this.#background = this.#root.getElementById("background");
          this.#container = this.#root.getElementById("container");
          this.#header = this.#root.getElementById("header");
          this.#footer = this.#root.getElementById("footer");
          this.#observer.observe(this.#container);
          this.#container.addEventListener("scroll", () => {
            this.dispatchEvent(new Event("scroll"));
            if (this.scrolled && !this.#justAnchored) {
              this.#maybeCrossSectionBoundary();
            }
          });
          this.#container.addEventListener("scroll", debounce(() => {
            if (this.scrolled) {
              if (this.#justAnchored) this.#justAnchored = false;
              else this.#afterScroll("scroll");
            }
          }, 250));
          const opts = { passive: false };
          this.addEventListener("touchstart", this.#onTouchStart.bind(this), opts);
          this.addEventListener("touchmove", this.#onTouchMove.bind(this), opts);
          this.addEventListener("touchend", this.#onTouchEnd.bind(this));
          this.addEventListener("load", ({ detail: { doc } }) => {
            doc.addEventListener("touchstart", this.#onTouchStart.bind(this), opts);
            doc.addEventListener("touchmove", this.#onTouchMove.bind(this), opts);
            doc.addEventListener("touchend", this.#onTouchEnd.bind(this));
          });
          this.addEventListener("relocate", ({ detail }) => {
            if (detail.reason === "selection") setSelectionTo(this.#anchor, 0);
            else if (detail.reason === "navigation") {
              if (this.#anchor === 1) setSelectionTo(detail.range, 1);
              else if (typeof this.#anchor === "number")
                setSelectionTo(detail.range, -1);
              else setSelectionTo(this.#anchor, -1);
            }
          });
          const checkPointerSelection = debounce((range, sel) => {
            if (!sel.rangeCount) return;
            const selRange = sel.getRangeAt(0);
            const backward = selectionIsBackward(sel);
            if (backward && selRange.compareBoundaryPoints(Range.START_TO_START, range) < 0)
              this.prev();
            else if (!backward && selRange.compareBoundaryPoints(Range.END_TO_END, range) > 0)
              this.next();
          }, 700);
          this.addEventListener("load", ({ detail: { doc } }) => {
            let isPointerSelecting = false;
            doc.addEventListener("pointerdown", () => isPointerSelecting = true);
            doc.addEventListener("pointerup", () => isPointerSelecting = false);
            let isKeyboardSelecting = false;
            doc.addEventListener("keydown", () => isKeyboardSelecting = true);
            doc.addEventListener("keyup", () => isKeyboardSelecting = false);
            doc.addEventListener("selectionchange", () => {
              if (this.scrolled) return;
              const range = this.#lastVisibleRange;
              if (!range) return;
              const sel = doc.getSelection();
              if (!sel.rangeCount) return;
              if (isPointerSelecting && sel.type === "Range")
                checkPointerSelection(range, sel);
              else if (isKeyboardSelecting) {
                const selRange = sel.getRangeAt(0).cloneRange();
                const backward = selectionIsBackward(sel);
                if (!backward) selRange.collapse();
                this.#scrollToAnchor(selRange);
              }
            });
            doc.addEventListener("focusin", (e3) => this.scrolled ? null : (
              // NOTE: `requestAnimationFrame` is needed in WebKit
              requestAnimationFrame(() => this.#scrollToAnchor(e3.target))
            ));
          });
          this.#mediaQueryListener = () => {
            if (!this.#view) return;
            this.#background.style.background = getBackground(this.#view.document);
          };
          this.#mediaQuery.addEventListener("change", this.#mediaQueryListener);
        }
        attributeChangedCallback(name, _2, value) {
          switch (name) {
            case "flow":
              this.render();
              if (this.scrolled && this.#view) this.#applyScrolledContainerAxis();
              if (this.#windowedScroll && this.scrolled && this.#view) this.#ensureWindow();
              break;
            case "gap":
            case "margin":
            case "max-block-size":
            case "max-column-count":
              this.#top.style.setProperty("--_" + name, value);
              break;
            case "max-inline-size":
              this.#top.style.setProperty("--_" + name, value);
              this.render();
              break;
          }
        }
        open(book) {
          this.bookDir = book.dir;
          this.sections = book.sections;
          book.transformTarget?.addEventListener("data", ({ detail }) => {
            if (detail.type !== "text/css") return;
            const w2 = innerWidth;
            const h3 = innerHeight;
            detail.data = Promise.resolve(detail.data).then((data) => data.replace(/(?<=[{\s;])-epub-/gi, "").replace(/(\d*\.?\d+)vw/gi, (_2, d2) => parseFloat(d2) * w2 / 100 + "px").replace(/(\d*\.?\d+)vh/gi, (_2, d2) => parseFloat(d2) * h3 / 100 + "px").replace(/page-break-(after|before|inside)\s*:/gi, (_2, x3) => `-webkit-column-break-${x3}:`).replace(/break-(after|before|inside)\s*:\s*(avoid-)?page/gi, (_2, x3, y3) => `break-${x3}: ${y3 ?? ""}column`));
          });
        }
        #createView() {
          if (this.#scrolledViews.length) {
            for (const v3 of this.#scrolledViews) {
              v3.destroy();
              if (v3.element.parentNode === this.#container) this.#container.removeChild(v3.element);
              this.sections[v3.wi73Index]?.unload?.();
            }
            this.#scrolledViews = [];
          }
          this.#mountingIndices.clear();
          this.#windowGeneration++;
          if (this.#view) {
            this.#view.destroy();
            this.#container.removeChild(this.#view.element);
          }
          this.#view = new View({
            container: this,
            onExpand: () => this.#scrollToAnchor(this.#anchor)
          });
          this.#container.append(this.#view.element);
          return this.#view;
        }
        // Feature #73 WI-1a: the mounted-view resolvers — the single seam every
        // `#view` consumer will route through. With `#windowedScroll` OFF these
        // return exactly the single `#view`, so behaviour is unchanged; WI-2 fills
        // `#scrolledViews` and WI-5 makes `#currentView()` scroll-position-aware.
        #mountedViews() {
          if (this.#windowedScroll && this.#scrolledViews.length) return this.#windowedViews();
          return this.#view ? [this.#view] : [];
        }
        #currentView() {
          return this.#view;
        }
        // Feature #73 WI-2: the windowed-mount primitives (scrolled-gated). These
        // mount NEIGHBOUR sections around the current `#view` into `#scrolledViews`
        // (in section order) so the continuous surface spans more than one section.
        // The current `#view` stays managed by `#createView`/`#display`; eviction
        // (WI-4) and swap replacement (WI-3) build on these.
        #windowRange(current, total, k3) {
          if (total <= 0 || k3 <= 0) return null;
          const size = Math.min(k3, total);
          const c2 = Math.min(Math.max(current, 0), total - 1);
          const half = Math.floor((size - 1) / 2);
          let lo = c2 - half;
          let hi = c2 + (size - 1 - half);
          if (lo < 0) {
            hi += -lo;
            lo = 0;
          }
          if (hi > total - 1) {
            lo -= hi - (total - 1);
            hi = total - 1;
          }
          return [Math.max(0, lo), hi];
        }
        #applyCachedStyles(doc) {
          const $$styles = this.#styleMap.get(doc);
          if (!$$styles) return;
          const [$beforeStyle, $style] = $$styles;
          const s3 = this.#styles;
          if (Array.isArray(s3)) {
            $beforeStyle.textContent = s3[0] ?? "";
            $style.textContent = s3[1] ?? "";
          } else if (s3 != null) $style.textContent = s3;
        }
        // Gate-4 round-2 M (audit): unload a section only if the CURRENT generation no
        // longer owns it — i.e. it is neither the anchor (#index) nor a mounted
        // neighbour. An index-only unload from a stale/failed mount could revoke
        // loader resources the fresh window load owns.
        #unloadIfUnowned(index) {
          if (index === this.#index) return;
          if (this.#scrolledViews.some((v3) => v3.wi73Index === index)) return;
          this.sections[index]?.unload?.();
        }
        async #mountSection(index) {
          if (!this.#canGoToIndex(index)) return null;
          if (index === this.#index) return null;
          if (this.#scrolledViews.some((v3) => v3.wi73Index === index)) return null;
          if (this.#mountingIndices.has(index)) return null;
          this.#mountingIndices.add(index);
          const gen = this.#windowGeneration;
          try {
            const src = await Promise.resolve(this.sections[index].load());
            if (gen !== this.#windowGeneration || !this.#windowedScroll || !this.scrolled) {
              this.#unloadIfUnowned(index);
              return null;
            }
            const view2 = new View({ container: this, onExpand: () => this.#onNeighbourExpand(view2) });
            view2.wi73Index = index;
            view2.wi73Height = 0;
            const ordered = [this.#view, ...this.#scrolledViews].filter((v3) => v3 && v3.element?.parentNode === this.#container).map((v3) => ({ el: v3.element, idx: v3.wi73Index ?? this.#index })).sort((a3, b3) => a3.idx - b3.idx);
            const below = ordered.filter((m3) => m3.idx < index);
            if (below.length) {
              const afterEl = below[below.length - 1].el;
              if (afterEl.nextSibling) this.#container.insertBefore(view2.element, afterEl.nextSibling);
              else this.#container.append(view2.element);
            } else if (ordered.length) {
              this.#container.insertBefore(view2.element, ordered[0].el);
            } else {
              this.#container.append(view2.element);
            }
            this.#scrolledViews.push(view2);
            this.#scrolledViews.sort((a3, b3) => a3.wi73Index - b3.wi73Index);
            const afterLoad = (doc) => {
              if (doc.head) {
                const $styleBefore = doc.createElement("style");
                doc.head.prepend($styleBefore);
                if (window.__vreaderForceVerticalRL) {
                  $styleBefore.textContent = ":root,html,body{writing-mode:vertical-rl!important;-webkit-writing-mode:vertical-rl!important}";
                  doc.documentElement?.style.setProperty("writing-mode", "vertical-rl", "important");
                  doc.body?.style.setProperty("writing-mode", "vertical-rl", "important");
                }
                const $style = doc.createElement("style");
                doc.head.append($style);
                this.#styleMap.set(doc, [$styleBefore, $style]);
                this.#applyCachedStyles(doc);
              }
            };
            try {
              await view2.load(src, afterLoad, this.#beforeRender.bind(this));
            } catch (e3) {
              view2.destroy();
              if (view2.element.parentNode === this.#container) this.#container.removeChild(view2.element);
              this.#scrolledViews = this.#scrolledViews.filter((v3) => v3 !== view2);
              this.#unloadIfUnowned(index);
              throw e3;
            }
            if (gen !== this.#windowGeneration || !this.#windowedScroll || !this.scrolled) {
              view2.destroy();
              if (view2.element.parentNode === this.#container) this.#container.removeChild(view2.element);
              this.#scrolledViews = this.#scrolledViews.filter((v3) => v3 !== view2);
              this.#unloadIfUnowned(index);
              return null;
            }
            this.dispatchEvent(new CustomEvent("load", { detail: { doc: view2.document, index } }));
            this.dispatchEvent(new CustomEvent("create-overlayer", {
              detail: {
                doc: view2.document,
                index,
                attach: (overlayer) => view2.overlayer = overlayer
              }
            }));
            return view2;
          } finally {
            this.#mountingIndices.delete(index);
          }
        }
        // Feature #76 WI-3: the active section's scroll model (axis/props/sign),
        // mirroring Swift FoliateScrollModel. The windowed primitives below read the
        // axis through these helpers instead of hardcoding scrollTop/height/top, so
        // the horizontal-writing (#73) path resolves to the IDENTICAL expressions
        // (scrollProp=scrollTop, sizeProp=height, rectStartProp=top, sign=+1) while a
        // vertical-writing section can later drive the horizontal axis. Defaults to
        // the horizontal-tb model when no view is mounted.
        get #activeScrollModel() {
          return this.#view?.scrollModel ?? scrollModelFor("horizontal-tb");
        }
        // Feature #76 WI-2: lay out scrolled-mode sections along the ACTIVE SCROLL
        // AXIS, so the windowed surface (WI-3) accumulates in the right direction.
        // Horizontal-writing (vertical scroll, axis='vertical') keeps the default
        // BLOCK stacking — no inline style is set, so the #73 path is byte-identical.
        // Vertical-writing (horizontal scroll, axis='horizontal') stacks sections in
        // a flex row so they accumulate along the horizontal axis; vertical-rl
        // (directionSign < 0, later content extends leftward) uses `row-reverse`.
        // Idempotent + reversible (a re-display with a different writing-mode resets
        // the inline style), and called from #display BEFORE the windowing gate so it
        // applies even while #ensureWindow still returns early for vertical (WI-3
        // removes that gate).
        #applyScrolledContainerAxis() {
          const m3 = this.#activeScrollModel;
          if (m3.axis === "horizontal") {
            this.#container.style.display = "flex";
            this.#container.style.flexDirection = "row";
            this.#container.style.direction = m3.directionSign < 0 ? "rtl" : "ltr";
          } else {
            this.#container.style.removeProperty("display");
            this.#container.style.removeProperty("flex-direction");
            this.#container.style.removeProperty("direction");
          }
        }
        // Logical (non-negative, reading-order) scroll offset of the container along
        // the active axis. For vertical-rl, WebKit's `scrollLeft` is negative toward
        // later content, so the sign maps it positive. horizontal-tb: == scrollTop.
        #axisScrollOffset() {
          const m3 = this.#activeScrollModel;
          const raw = this.#container[m3.scrollProp];
          return m3.directionSign < 0 ? -raw : raw;
        }
        #setAxisScrollOffset(logical) {
          const m3 = this.#activeScrollModel;
          this.#container[m3.scrollProp] = m3.directionSign < 0 ? -logical : logical;
        }
        // Element extent along the active axis. horizontal-tb: == rect.height.
        #elementAxisSize(el) {
          return Math.max(0, el.getBoundingClientRect()[this.#activeScrollModel.sizeProp]);
        }
        // Feature #76 WI-3: the container's total scroll extent + viewport size along
        // the active axis (horizontal-tb: scrollHeight / clientHeight; vertical-
        // writing: scrollWidth / clientWidth). Used by the windowed `#scrollNext`
        // remaining-room check so it works on the horizontal scroll axis too.
        #axisScrollSize() {
          return this.#container[this.#activeScrollModel.sizeProp === "width" ? "scrollWidth" : "scrollHeight"];
        }
        #axisClientSize() {
          return this.#container[this.#activeScrollModel.sizeProp === "width" ? "clientWidth" : "clientHeight"];
        }
        // Element's logical start offset within the container's scroll content along
        // the active axis (axis-aware generalization of the old #elementScrollTop).
        // horizontal-tb: rect.top - container.top + scrollTop — byte-identical.
        #elementAxisStart(el) {
          const m3 = this.#activeScrollModel;
          const rawDelta = el.getBoundingClientRect()[m3.rectStartProp] - this.#container.getBoundingClientRect()[m3.rectStartProp];
          return (m3.directionSign < 0 ? -rawDelta : rawDelta) + this.#axisScrollOffset();
        }
        // WI-6c: when a mounted neighbour's size changes after layout (fonts.ready,
        // image load, reflow), shift the axis scroll offset by the delta IF the
        // neighbour sits before the current scroll position — so visible content
        // does not jump. (#76 WI-3: axis-aware; horizontal-tb == the old scrollTop+height path.)
        #onNeighbourExpand(view2) {
          if (!this.#windowedScroll || !view2?.element) return;
          const prev = view2.wi73Height ?? 0;
          const now = this.#elementAxisSize(view2.element);
          view2.wi73Height = now;
          const delta = now - prev;
          if (delta === 0) return;
          if (this.#elementAxisStart(view2.element) < this.#axisScrollOffset()) {
            this.#setAxisScrollOffset(Math.max(0, this.#axisScrollOffset() + delta));
          }
        }
        async #ensureWindow() {
          if (!this.#windowedScroll || !this.scrolled) return;
          const range = this.#windowRange(this.#index, this.sections.length, this.#K);
          if (!range) return;
          const [lo, hi] = range;
          for (let i3 = lo; i3 <= hi; i3++) {
            if (i3 === this.#index) continue;
            if (!this.#scrolledViews.some((v3) => v3.wi73Index === i3)) {
              try {
                await this.#mountSection(i3);
              } catch (e3) {
                console.warn("WI73 mount", i3, e3);
              }
            }
          }
          this.#evictOutsideWindow(lo, hi);
        }
        // Feature #73 WI-4: bound memory to the K-window. Unmount + unload any
        // neighbour outside [lo,hi]; the anchor `#view` (#index) is never in
        // `#scrolledViews` so it can't be evicted. Evicting a section ABOVE the
        // viewport removes content above the scroll position, shifting everything
        // up — so subtract the evicted-above heights from `scrollTop` to keep the
        // visible content stationary (FoliateScrolledWindowMath.offsetAdjustmentOnEvict).
        #evictOutsideWindow(lo, hi) {
          const keep = [];
          let scrollAdjust = 0;
          for (const v3 of this.#scrolledViews) {
            const idx = v3.wi73Index;
            if (idx >= lo && idx <= hi) {
              keep.push(v3);
              continue;
            }
            if (idx < this.#index) {
              scrollAdjust += this.#elementAxisSize(v3.element);
            }
            v3.destroy();
            if (v3.element.parentNode === this.#container) this.#container.removeChild(v3.element);
            this.sections[idx]?.unload?.();
          }
          this.#scrolledViews = keep;
          if (scrollAdjust > 0) {
            this.#setAxisScrollOffset(Math.max(0, this.#axisScrollOffset() - scrollAdjust));
          }
        }
        // Feature #73 WI-3/WI-5: resolve the CURRENT section + intra-section fraction
        // from the live scroll position over the mounted views (the anchor `#view`
        // plus its neighbours), so windowed crossing is native scroll — no swap.
        #elementScrollTop(el) {
          return this.#elementAxisStart(el);
        }
        #windowedViews() {
          return [this.#view, ...this.#scrolledViews].filter(Boolean).sort((a3, b3) => (a3.wi73Index ?? this.#index) - (b3.wi73Index ?? this.#index));
        }
        #windowedResolve() {
          const views = this.#windowedViews();
          if (!views.length) return { view: this.#view, index: this.#index, intra: 0 };
          if (this.#view && this.#view.wi73Index == null) this.#view.wi73Index = this.#index;
          const offset = this.#axisScrollOffset();
          for (const v3 of views) {
            const start = this.#elementAxisStart(v3.element);
            const size = this.#elementAxisSize(v3.element);
            if (offset < start + size - 1) {
              const idx = v3.wi73Index ?? this.#index;
              const intra = size > 0 ? Math.min(Math.max((offset - start) / size, 0), 1) : 0;
              return { view: v3, index: idx, intra };
            }
          }
          const last = views[views.length - 1];
          return { view: last, index: last.wi73Index ?? this.#index, intra: 1 };
        }
        // Feature #73 WI-6a: keep `#view` pointing at the section the viewport top is
        // in — a POINTER swap, not a DOM move (no flash). After a swap-free crossing
        // the single-`#view` getters (viewSize / pages / #getRectMapper /
        // getVisibleRange / #background / atStart / atEnd) all read the correct
        // section. The old `#view` is demoted into `#scrolledViews` (it stays mounted
        // in the container); the resolved view leaves `#scrolledViews` to become `#view`.
        #promoteCurrentView(resolved) {
          if (!resolved?.view || resolved.view === this.#view) {
            if (resolved) this.#index = resolved.index;
            return;
          }
          const old = this.#view;
          if (old) {
            if (old.wi73Index == null) old.wi73Index = this.#index;
            if (!this.#scrolledViews.includes(old)) this.#scrolledViews.push(old);
          }
          this.#scrolledViews = this.#scrolledViews.filter((v3) => v3 !== resolved.view);
          this.#view = resolved.view;
          this.#index = resolved.index;
          if (this.#view?.document) this.#background.style.background = getBackground(this.#view.document);
        }
        // Feature #73 WI-6b: `start` is container-absolute (it spans every view
        // mounted ABOVE the current one). Per-`#view` document operations need the
        // offset RELATIVE to the current view's position in the container. Flag OFF
        // (or no neighbours) → one view at offset 0 → relative == absolute.
        #viewRelativeStart() {
          if (!this.#windowedScroll || !this.#view) return this.start;
          return Math.max(0, this.#axisScrollOffset() - this.#elementScrollTop(this.#view.element));
        }
        #beforeRender({ vertical, rtl, background }) {
          this.#vertical = vertical;
          this.#rtl = rtl;
          this.#top.classList.toggle("vertical", vertical);
          this.#background.style.background = background;
          const { width, height } = this.#container.getBoundingClientRect();
          const size = vertical ? height : width;
          const style = getComputedStyle(this.#top);
          const maxInlineSize = parseFloat(style.getPropertyValue("--_max-inline-size"));
          const maxColumnCount = parseInt(style.getPropertyValue("--_max-column-count-spread"));
          const margin = parseFloat(style.getPropertyValue("--_margin"));
          this.#margin = margin;
          const g3 = parseFloat(style.getPropertyValue("--_gap")) / 100;
          const gap = -g3 / (g3 - 1) * size;
          const flow = this.getAttribute("flow");
          if (flow === "scrolled") {
            this.setAttribute("dir", vertical ? "rtl" : "ltr");
            this.#top.style.padding = "0";
            const columnWidth2 = maxInlineSize;
            this.heads = null;
            this.feet = null;
            this.#header.replaceChildren();
            this.#footer.replaceChildren();
            return { flow, margin, gap, columnWidth: columnWidth2 };
          }
          const divisor = Math.min(maxColumnCount, Math.ceil(size / maxInlineSize));
          const columnWidth = size / divisor - gap;
          this.setAttribute("dir", rtl ? "rtl" : "ltr");
          const marginalDivisor = vertical ? Math.min(2, Math.ceil(width / maxInlineSize)) : divisor;
          const marginalStyle = {
            gridTemplateColumns: `repeat(${marginalDivisor}, 1fr)`,
            gap: `${gap}px`,
            direction: this.bookDir === "rtl" ? "rtl" : "ltr"
          };
          Object.assign(this.#header.style, marginalStyle);
          Object.assign(this.#footer.style, marginalStyle);
          const heads = makeMarginals(marginalDivisor, "head");
          const feet = makeMarginals(marginalDivisor, "foot");
          this.heads = heads.map((el) => el.children[0]);
          this.feet = feet.map((el) => el.children[0]);
          this.#header.replaceChildren(...heads);
          this.#footer.replaceChildren(...feet);
          return { height, width, margin, gap, columnWidth };
        }
        render() {
          if (!this.#view) return;
          const layout = this.#beforeRender({
            vertical: this.#vertical,
            rtl: this.#rtl
          });
          for (const v3 of this.#scrolledViews) v3.render(layout);
          this.#view.render(layout);
          this.#scrollToAnchor(this.#anchor);
        }
        get scrolled() {
          return this.getAttribute("flow") === "scrolled";
        }
        get scrollProp() {
          const { scrolled } = this;
          return this.#vertical ? scrolled ? "scrollLeft" : "scrollTop" : scrolled ? "scrollTop" : "scrollLeft";
        }
        get sideProp() {
          const { scrolled } = this;
          return this.#vertical ? scrolled ? "width" : "height" : scrolled ? "height" : "width";
        }
        get size() {
          return this.#container.getBoundingClientRect()[this.sideProp];
        }
        get viewSize() {
          return this.#view.element.getBoundingClientRect()[this.sideProp];
        }
        get start() {
          return Math.abs(this.#container[this.scrollProp]);
        }
        get end() {
          return this.start + this.size;
        }
        get page() {
          return Math.floor((this.start + this.end) / 2 / this.size);
        }
        get pages() {
          return Math.round(this.viewSize / this.size);
        }
        scrollBy(dx, dy) {
          const delta = this.#vertical ? dy : dx;
          const element = this.#container;
          const { scrollProp } = this;
          const [offset, a3, b3] = this.#scrollBounds;
          const rtl = this.#rtl;
          const min = rtl ? offset - b3 : offset - a3;
          const max = rtl ? offset + a3 : offset + b3;
          element[scrollProp] = Math.max(min, Math.min(
            max,
            element[scrollProp] + delta
          ));
        }
        snap(vx, vy) {
          const velocity = this.#vertical ? vy : vx;
          const [offset, a3, b3] = this.#scrollBounds;
          const { start, end, pages, size } = this;
          const min = Math.abs(offset) - a3;
          const max = Math.abs(offset) + b3;
          const d2 = velocity * (this.#rtl ? -size : size);
          const page = Math.floor(
            Math.max(min, Math.min(max, (start + end) / 2 + (isNaN(d2) ? 0 : d2))) / size
          );
          this.#scrollToPage(page, "snap").then(() => {
            const dir = page <= 0 ? -1 : page >= pages - 1 ? 1 : null;
            if (dir) return this.#goTo({
              index: this.#adjacentIndex(dir),
              anchor: dir < 0 ? () => 1 : () => 0
            });
          });
        }
        #onTouchStart(e3) {
          const touch = e3.changedTouches[0];
          this.#touchState = {
            x: touch?.screenX,
            y: touch?.screenY,
            t: e3.timeStamp,
            vx: 0,
            xy: 0
          };
        }
        #onTouchMove(e3) {
          const state = this.#touchState;
          if (state.pinched) return;
          state.pinched = globalThis.visualViewport.scale > 1;
          if (this.scrolled || state.pinched) return;
          if (e3.touches.length > 1) {
            if (this.#touchScrolled) e3.preventDefault();
            return;
          }
          e3.preventDefault();
          const touch = e3.changedTouches[0];
          const x3 = touch.screenX, y3 = touch.screenY;
          const dx = state.x - x3, dy = state.y - y3;
          const dt2 = e3.timeStamp - state.t;
          state.x = x3;
          state.y = y3;
          state.t = e3.timeStamp;
          state.vx = dx / dt2;
          state.vy = dy / dt2;
          this.#touchScrolled = true;
          this.scrollBy(dx, dy);
        }
        #onTouchEnd() {
          this.#touchScrolled = false;
          if (this.scrolled) return;
          requestAnimationFrame(() => {
            if (globalThis.visualViewport.scale === 1)
              this.snap(this.#touchState.vx, this.#touchState.vy);
          });
        }
        // allows one to process rects as if they were LTR and horizontal
        #getRectMapper() {
          if (this.scrolled) {
            const size = this.viewSize;
            const margin = this.#margin;
            const m3 = this.#activeScrollModel;
            if (m3.axis === "horizontal") {
              return m3.directionSign < 0 ? ({ left, right }) => ({ left: size - right - margin, right: size - left - margin }) : ({ left, right }) => ({ left: left + margin, right: right + margin });
            }
            return ({ top, bottom }) => ({ left: top + margin, right: bottom + margin });
          }
          const pxSize = this.pages * this.size;
          return this.#rtl ? ({ left, right }) => ({ left: pxSize - right, right: pxSize - left }) : this.#vertical ? ({ top, bottom }) => ({ left: top, right: bottom }) : (f3) => f3;
        }
        async #scrollToRect(rect, reason) {
          if (this.scrolled) {
            let offset2 = this.#getRectMapper()(rect).left - this.#margin;
            if (this.#windowedScroll && this.#view) offset2 += this.#elementScrollTop(this.#view.element);
            return this.#scrollTo(offset2, reason);
          }
          const offset = this.#getRectMapper()(rect).left;
          return this.#scrollToPage(Math.floor(offset / this.size) + (this.#rtl ? -1 : 1), reason);
        }
        async #scrollTo(offset, reason, smooth) {
          const element = this.#container;
          const { scrollProp, size } = this;
          if (this.scrolled && this.#activeScrollModel.directionSign < 0) offset = -offset;
          if (element[scrollProp] === offset) {
            this.#scrollBounds = [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size];
            this.#afterScroll(reason);
            return;
          }
          if ((reason === "snap" || smooth) && this.hasAttribute("animated")) return animate(
            element[scrollProp],
            offset,
            300,
            easeOutQuad,
            (x3) => element[scrollProp] = x3
          ).then(() => {
            this.#scrollBounds = [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size];
            this.#afterScroll(reason);
          });
          else {
            element[scrollProp] = offset;
            this.#scrollBounds = [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size];
            this.#afterScroll(reason);
          }
        }
        async #scrollToPage(page, reason, smooth) {
          const offset = this.size * (this.#rtl ? -page : page);
          return this.#scrollTo(offset, reason, smooth);
        }
        async scrollToAnchor(anchor, select) {
          return this.#scrollToAnchor(anchor, select ? "selection" : "navigation");
        }
        async #scrollToAnchor(anchor, reason = "anchor") {
          this.#anchor = anchor;
          const rects = uncollapse(anchor)?.getClientRects?.();
          if (rects) {
            const rect = Array.from(rects).find((r3) => r3.width > 0 && r3.height > 0) || rects[0];
            if (!rect) return;
            await this.#scrollToRect(rect, reason);
            return;
          }
          if (this.scrolled) {
            let offset = anchor * this.viewSize;
            if (this.#windowedScroll && this.#view) offset += this.#elementScrollTop(this.#view.element);
            await this.#scrollTo(offset, reason);
            return;
          }
          const { pages } = this;
          if (!pages) return;
          const textPages = pages - 2;
          const newPage = Math.round(anchor * (textPages - 1));
          await this.#scrollToPage(newPage + 1, reason);
        }
        #getVisibleRange() {
          if (this.scrolled) {
            const vStart = this.#viewRelativeStart();
            const vEnd = vStart + this.size;
            return getVisibleRange(
              this.#view.document,
              vStart + this.#margin,
              vEnd - this.#margin,
              this.#getRectMapper()
            );
          }
          const size = this.#rtl ? -this.size : this.size;
          return getVisibleRange(
            this.#view.document,
            this.start - size,
            this.end - size,
            this.#getRectMapper()
          );
        }
        #afterScroll(reason) {
          let scrolledFraction = null;
          if (this.scrolled && this.#windowedScroll) {
            const r3 = this.#windowedResolve();
            this.#promoteCurrentView(r3);
            scrolledFraction = r3.intra;
            this.#ensureWindow();
          }
          const range = this.#getVisibleRange();
          this.#lastVisibleRange = range;
          if (reason !== "selection" && reason !== "navigation" && reason !== "anchor")
            this.#anchor = range;
          else this.#justAnchored = true;
          const index = this.#index;
          const detail = { reason, range, index };
          if (this.scrolled) detail.fraction = scrolledFraction != null ? scrolledFraction : this.start / this.viewSize;
          else if (this.pages > 0) {
            const { page, pages } = this;
            this.#header.style.visibility = page > 1 ? "visible" : "hidden";
            detail.fraction = (page - 1) / (pages - 2);
            detail.size = 1 / (pages - 2);
          }
          this.dispatchEvent(new CustomEvent("relocate", { detail }));
        }
        async #display(promise) {
          const { index, src, anchor, onLoad, select } = await promise;
          this.#index = index;
          const hasFocus = this.#view?.document?.hasFocus();
          if (src) {
            const view2 = this.#createView();
            const afterLoad = (doc) => {
              if (doc.head) {
                const $styleBefore = doc.createElement("style");
                doc.head.prepend($styleBefore);
                if (window.__vreaderForceVerticalRL) {
                  $styleBefore.textContent = ":root,html,body{writing-mode:vertical-rl!important;-webkit-writing-mode:vertical-rl!important}";
                  doc.documentElement?.style.setProperty("writing-mode", "vertical-rl", "important");
                  doc.body?.style.setProperty("writing-mode", "vertical-rl", "important");
                }
                const $style = doc.createElement("style");
                doc.head.append($style);
                this.#styleMap.set(doc, [$styleBefore, $style]);
              }
              onLoad?.({ doc, index });
            };
            const beforeRender = this.#beforeRender.bind(this);
            await view2.load(src, afterLoad, beforeRender);
            this.dispatchEvent(new CustomEvent("create-overlayer", {
              detail: {
                doc: view2.document,
                index,
                attach: (overlayer) => view2.overlayer = overlayer
              }
            }));
            this.#view = view2;
          }
          await this.scrollToAnchor((typeof anchor === "function" ? anchor(this.#view.document) : anchor) ?? 0, select);
          if (hasFocus) this.focusView();
          if (this.scrolled) this.#applyScrolledContainerAxis();
          if (this.scrolled && this.#windowedScroll) this.#ensureWindow();
        }
        #canGoToIndex(index) {
          return index >= 0 && index <= this.sections.length - 1;
        }
        async #goTo({ index, anchor, select }) {
          if (index === this.#index) await this.#display({ index, anchor, select });
          else {
            const oldIndex = this.#index;
            const onLoad = (detail) => {
              this.sections[oldIndex]?.unload?.();
              this.setStyles(this.#styles);
              this.dispatchEvent(new CustomEvent("load", { detail }));
            };
            await this.#display(Promise.resolve(this.sections[index].load()).then((src) => ({ index, src, anchor, onLoad, select })).catch((e3) => {
              console.warn(e3);
              console.warn(new Error(`Failed to load section ${index}`));
              return {};
            }));
          }
        }
        async goTo(target) {
          if (this.#locked) return;
          const resolved = await target;
          if (this.#canGoToIndex(resolved.index)) return this.#goTo(resolved);
        }
        #scrollPrev(distance) {
          if (!this.#view) return true;
          if (this.scrolled) {
            if (this.#windowedScroll) {
              const offset = this.#axisScrollOffset();
              if (offset > 0) return this.#scrollTo(Math.max(0, offset - (distance ?? this.size)), null, true);
              return this.#adjacentIndex(-1) != null;
            }
            if (this.start > 0) return this.#scrollTo(
              Math.max(0, this.start - (distance ?? this.size)),
              null,
              true
            );
            return true;
          }
          if (this.atStart) return;
          const page = this.page - 1;
          return this.#scrollToPage(page, "page", true).then(() => page <= 0);
        }
        #scrollNext(distance) {
          if (!this.#view) return true;
          if (this.scrolled) {
            if (this.#windowedScroll) {
              const offset = this.#axisScrollOffset();
              const remaining = this.#axisScrollSize() - (offset + this.#axisClientSize());
              if (remaining > 2) return this.#scrollTo(offset + (distance ?? this.size), null, true);
              return this.#adjacentIndex(1) != null;
            }
            if (this.viewSize - this.end > 2) return this.#scrollTo(
              Math.min(this.viewSize, distance ? this.start + distance : this.end),
              null,
              true
            );
            return true;
          }
          if (this.atEnd) return;
          const page = this.page + 1;
          const pages = this.pages;
          return this.#scrollToPage(page, "page", true).then(() => page >= pages - 1);
        }
        get atStart() {
          return this.#adjacentIndex(-1) == null && this.page <= 1;
        }
        get atEnd() {
          return this.#adjacentIndex(1) == null && this.page >= this.pages - 2;
        }
        #adjacentIndex(dir) {
          for (let index = this.#index + dir; this.#canGoToIndex(index); index += dir)
            if (this.sections[index]?.linear !== "no") return index;
        }
        async #turnPage(dir, distance) {
          if (this.#locked) return;
          this.#locked = true;
          const prev = dir === -1;
          const shouldGo = await (prev ? this.#scrollPrev(distance) : this.#scrollNext(distance));
          if (shouldGo) await this.#goTo({
            index: this.#adjacentIndex(dir),
            anchor: prev ? () => 1 : () => 0
          });
          if (shouldGo || !this.hasAttribute("animated")) await wait(100);
          this.#locked = false;
        }
        // Bug #235 (GH #983): cross-section continuity for scrolled mode.
        // Native scrolling alone cannot leave the current section because
        // each section is rendered into a single iframe-backed #view; the
        // user hits the section edge and stops. Detect that edge DURING
        // the live scroll (called from the immediate scroll listener that
        // fires every native scroll event, ~60Hz under a fling) and feed
        // the result through the same #turnPage() pipeline that programmatic
        // next()/prev() uses — so the user gets a continuous reading flow
        // without any new chrome and without the quarter-second lag a
        // post-settle debounce would impose. The separate 250ms-debounced
        // listener still owns relocate / anchor maintenance (it calls
        // #afterScroll('scroll') so other observers see the new offset).
        //
        // Gates:
        //   * scrolled mode only — paged mode already advances sections via
        //     #scrollNext / #scrollPrev's page-bound exhaustion path.
        //   * not locked — #turnPage owns the transition lock; firing here
        //     while another transition is in flight would double-advance
        //     and drop the user's position.
        //   * #view exists — guards against firing during teardown.
        //   * adjacent section exists in the same direction — guards
        //     against scrolling past the first/last chapter.
        //
        // Re-entrancy under fling: the immediate listener fires per scroll
        // event. The first time atEnd/atStart resolves true, we call
        // #turnPage(±1), which sets #locked=true synchronously (before its
        // first await). Subsequent same-fling scroll events then short-
        // circuit on `#locked`. The new section's programmatic
        // scrollToAnchor sets #justAnchored=true, which the immediate
        // listener checks before invoking this helper, so the post-load
        // landing scroll events do not re-trigger a cross-section advance.
        //
        // Boundary epsilons mirror upstream Foliate's own asymmetric
        // thresholds so this helper does not fire one frame earlier than
        // #scrollPrev / #scrollNext would on the same input:
        //   atEnd matches #scrollNext's "viewSize - end > 2" (2px slack
        //     for sub-pixel residual after animated scrollTo).
        //   atStart matches #scrollPrev's "start > 0" (no slack — start
        //     is clamped at 0 by native scroll).
        #maybeCrossSectionBoundary() {
          if (!this.scrolled) return;
          if (this.#locked) return;
          if (!this.#view) return;
          if (this.#windowedScroll) {
            const r3 = this.#windowedResolve();
            this.#promoteCurrentView(r3);
            this.#ensureWindow();
            return;
          }
          const atEnd = this.viewSize - this.end <= 2;
          const atStart = this.start <= 0;
          if (atEnd && this.#adjacentIndex(1) != null) {
            this.#turnPage(1);
          } else if (atStart && this.#adjacentIndex(-1) != null) {
            this.#turnPage(-1);
          }
        }
        prev(distance) {
          return this.#turnPage(-1, distance);
        }
        next(distance) {
          return this.#turnPage(1, distance);
        }
        prevSection() {
          return this.goTo({ index: this.#adjacentIndex(-1) });
        }
        nextSection() {
          return this.goTo({ index: this.#adjacentIndex(1) });
        }
        firstSection() {
          const index = this.sections.findIndex((section) => section.linear !== "no");
          return this.goTo({ index });
        }
        lastSection() {
          const index = this.sections.findLastIndex((section) => section.linear !== "no");
          return this.goTo({ index });
        }
        getContents() {
          return this.#mountedViews().map((v3) => ({
            index: v3.wi73Index ?? this.#index,
            // WI-7: each mounted view carries its own section index
            overlayer: v3.overlayer,
            doc: v3.document
          }));
        }
        setStyles(styles) {
          this.#styles = styles;
          for (const view2 of this.#mountedViews()) {
            const $$styles = this.#styleMap.get(view2?.document);
            if (!$$styles) continue;
            const [$beforeStyle, $style] = $$styles;
            if (Array.isArray(styles)) {
              const [beforeStyle, style] = styles;
              $beforeStyle.textContent = beforeStyle;
              $style.textContent = style;
            } else $style.textContent = styles;
            view2?.document?.fonts?.ready?.then(() => view2.expand());
          }
          requestAnimationFrame(() => {
            if (this.#view?.document) this.#background.style.background = getBackground(this.#view.document);
          });
        }
        focusView() {
          this.#view.document.defaultView.focus();
        }
        destroy() {
          this.#observer.unobserve(this);
          for (const v3 of this.#scrolledViews) {
            v3.destroy();
            if (v3.element.parentNode === this.#container) this.#container.removeChild(v3.element);
            this.sections[v3.wi73Index]?.unload?.();
          }
          this.#scrolledViews = [];
          this.#mountingIndices.clear();
          this.#windowGeneration++;
          this.#view.destroy();
          this.#view = null;
          this.sections[this.#index]?.unload?.();
          this.#mediaQuery.removeEventListener("change", this.#mediaQueryListener);
        }
      };
      customElements.define("foliate-paginator", Paginator);
    }
  });

  // search.js
  var search_exports = {};
  __export(search_exports, {
    search: () => search,
    searchMatcher: () => searchMatcher
  });
  var CONTEXT_LENGTH, normalizeWhitespace2, makeExcerpt, simpleSearch, segmenterSearch, search, searchMatcher;
  var init_search = __esm({
    "search.js"() {
      CONTEXT_LENGTH = 50;
      normalizeWhitespace2 = (str) => str.replace(/\s+/g, " ");
      makeExcerpt = (strs, { startIndex, startOffset, endIndex, endOffset }) => {
        const start = strs[startIndex];
        const end = strs[endIndex];
        const match = start === end ? start.slice(startOffset, endOffset) : start.slice(startOffset) + strs.slice(start + 1, end).join("") + end.slice(0, endOffset);
        const trimmedStart = normalizeWhitespace2(start.slice(0, startOffset)).trimStart();
        const trimmedEnd = normalizeWhitespace2(end.slice(endOffset)).trimEnd();
        const ellipsisPre = trimmedStart.length < CONTEXT_LENGTH ? "" : "\u2026";
        const ellipsisPost = trimmedEnd.length < CONTEXT_LENGTH ? "" : "\u2026";
        const pre = `${ellipsisPre}${trimmedStart.slice(-CONTEXT_LENGTH)}`;
        const post2 = `${trimmedEnd.slice(0, CONTEXT_LENGTH)}${ellipsisPost}`;
        return { pre, match, post: post2 };
      };
      simpleSearch = function* (strs, query, options = {}) {
        const { locales = "en", sensitivity } = options;
        const matchCase = sensitivity === "variant";
        const haystack = strs.join("");
        const lowerHaystack = matchCase ? haystack : haystack.toLocaleLowerCase(locales);
        const needle = matchCase ? query : query.toLocaleLowerCase(locales);
        const needleLength = needle.length;
        let index = -1;
        let strIndex = -1;
        let sum = 0;
        do {
          index = lowerHaystack.indexOf(needle, index + 1);
          if (index > -1) {
            while (sum <= index) sum += strs[++strIndex].length;
            const startIndex = strIndex;
            const startOffset = index - (sum - strs[strIndex].length);
            const end = index + needleLength;
            while (sum <= end) sum += strs[++strIndex].length;
            const endIndex = strIndex;
            const endOffset = end - (sum - strs[strIndex].length);
            const range = { startIndex, startOffset, endIndex, endOffset };
            yield { range, excerpt: makeExcerpt(strs, range) };
          }
        } while (index > -1);
      };
      segmenterSearch = function* (strs, query, options = {}) {
        const { locales = "en", granularity = "word", sensitivity = "base" } = options;
        let segmenter, collator;
        try {
          segmenter = new Intl.Segmenter(locales, { usage: "search", granularity });
          collator = new Intl.Collator(locales, { sensitivity });
        } catch (e3) {
          console.warn(e3);
          segmenter = new Intl.Segmenter("en", { usage: "search", granularity });
          collator = new Intl.Collator("en", { sensitivity });
        }
        const queryLength = Array.from(segmenter.segment(query)).length;
        const substrArr = [];
        let strIndex = 0;
        let segments = segmenter.segment(strs[strIndex])[Symbol.iterator]();
        main: while (strIndex < strs.length) {
          while (substrArr.length < queryLength) {
            const { done, value } = segments.next();
            if (done) {
              strIndex++;
              if (strIndex < strs.length) {
                segments = segmenter.segment(strs[strIndex])[Symbol.iterator]();
                continue;
              } else break main;
            }
            const { index, segment } = value;
            if (!/[^\p{Format}]/u.test(segment)) continue;
            if (/\s/u.test(segment)) {
              if (!/\s/u.test(substrArr[substrArr.length - 1]?.segment))
                substrArr.push({ strIndex, index, segment: " " });
              continue;
            }
            value.strIndex = strIndex;
            substrArr.push(value);
          }
          const substr = substrArr.map((x3) => x3.segment).join("");
          if (collator.compare(query, substr) === 0) {
            const endIndex = strIndex;
            const lastSeg = substrArr[substrArr.length - 1];
            const endOffset = lastSeg.index + lastSeg.segment.length;
            const startIndex = substrArr[0].strIndex;
            const startOffset = substrArr[0].index;
            const range = { startIndex, startOffset, endIndex, endOffset };
            yield { range, excerpt: makeExcerpt(strs, range) };
          }
          substrArr.shift();
        }
      };
      search = (strs, query, options) => {
        const { granularity = "grapheme", sensitivity = "base" } = options;
        if (!Intl?.Segmenter || granularity === "grapheme" && (sensitivity === "variant" || sensitivity === "accent"))
          return simpleSearch(strs, query, options);
        return segmenterSearch(strs, query, options);
      };
      searchMatcher = (textWalker2, opts) => {
        const { defaultLocale, matchCase, matchDiacritics, matchWholeWords, acceptNode: acceptNode2 } = opts;
        return function* (doc, query) {
          const iter = textWalker2(doc, function* (strs, makeRange2) {
            for (const result of search(strs, query, {
              locales: doc.body.lang || doc.documentElement.lang || defaultLocale || "en",
              granularity: matchWholeWords ? "word" : "grapheme",
              sensitivity: matchDiacritics && matchCase ? "variant" : matchDiacritics && !matchCase ? "accent" : !matchDiacritics && matchCase ? "case" : "base"
            })) {
              const { startIndex, startOffset, endIndex, endOffset } = result.range;
              result.range = makeRange2(startIndex, startOffset, endIndex, endOffset);
              yield result;
            }
          }, acceptNode2);
          for (const result of iter) yield result;
        };
      };
    }
  });

  // tts.js
  var tts_exports = {};
  __export(tts_exports, {
    TTS: () => TTS
  });
  function* getBlocks(doc) {
    let last;
    const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_ELEMENT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const name = node.tagName.toLowerCase();
      if (blockTags.has(name)) {
        if (last) {
          last.setEndBefore(node);
          if (!rangeIsEmpty(last)) yield last;
        }
        last = doc.createRange();
        last.setStart(node, 0);
      }
    }
    if (!last) {
      last = doc.createRange();
      last.setStart(doc.body.firstChild ?? doc.body, 0);
    }
    last.setEndAfter(doc.body.lastChild ?? doc.body);
    if (!rangeIsEmpty(last)) yield last;
  }
  var NS2, blockTags, getLang, getAlphabet, getSegmenter, fragmentToSSML, getFragmentWithMarks, rangeIsEmpty, ListIterator, TTS;
  var init_tts = __esm({
    "tts.js"() {
      NS2 = {
        XML: "http://www.w3.org/XML/1998/namespace",
        SSML: "http://www.w3.org/2001/10/synthesis"
      };
      blockTags = /* @__PURE__ */ new Set([
        "article",
        "aside",
        "audio",
        "blockquote",
        "caption",
        "details",
        "dialog",
        "div",
        "dl",
        "dt",
        "dd",
        "figure",
        "footer",
        "form",
        "figcaption",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "header",
        "hgroup",
        "hr",
        "li",
        "main",
        "math",
        "nav",
        "ol",
        "p",
        "pre",
        "section",
        "tr"
      ]);
      getLang = (el) => {
        const x3 = el.lang || el?.getAttributeNS?.(NS2.XML, "lang");
        return x3 ? x3 : el.parentElement ? getLang(el.parentElement) : null;
      };
      getAlphabet = (el) => {
        const x3 = el?.getAttributeNS?.(NS2.XML, "lang");
        return x3 ? x3 : el.parentElement ? getAlphabet(el.parentElement) : null;
      };
      getSegmenter = (lang = "en", granularity = "word") => {
        const segmenter = new Intl.Segmenter(lang, { granularity });
        const granularityIsWord = granularity === "word";
        return function* (strs, makeRange2) {
          const str = strs.join("");
          let name = 0;
          let strIndex = -1;
          let sum = 0;
          for (const { index, segment, isWordLike } of segmenter.segment(str)) {
            if (granularityIsWord && !isWordLike) continue;
            while (sum <= index) sum += strs[++strIndex].length;
            const startIndex = strIndex;
            const startOffset = index - (sum - strs[strIndex].length);
            const end = index + segment.length - 1;
            if (end < str.length) while (sum <= end) sum += strs[++strIndex].length;
            const endIndex = strIndex;
            const endOffset = end - (sum - strs[strIndex].length) + 1;
            yield [
              (name++).toString(),
              makeRange2(startIndex, startOffset, endIndex, endOffset)
            ];
          }
        };
      };
      fragmentToSSML = (fragment, inherited) => {
        const ssml = document.implementation.createDocument(NS2.SSML, "speak");
        const { lang } = inherited;
        if (lang) ssml.documentElement.setAttributeNS(NS2.XML, "lang", lang);
        const convert = (node, parent, inheritedAlphabet) => {
          if (!node) return;
          if (node.nodeType === 3) return ssml.createTextNode(node.textContent);
          if (node.nodeType === 4) return ssml.createCDATASection(node.textContent);
          if (node.nodeType !== 1) return;
          let el;
          const nodeName = node.nodeName.toLowerCase();
          if (nodeName === "foliate-mark") {
            el = ssml.createElementNS(NS2.SSML, "mark");
            el.setAttribute("name", node.dataset.name);
          } else if (nodeName === "br")
            el = ssml.createElementNS(NS2.SSML, "break");
          else if (nodeName === "em" || nodeName === "strong")
            el = ssml.createElementNS(NS2.SSML, "emphasis");
          const lang2 = node.lang || node.getAttributeNS(NS2.XML, "lang");
          if (lang2) {
            if (!el) el = ssml.createElementNS(NS2.SSML, "lang");
            el.setAttributeNS(NS2.XML, "lang", lang2);
          }
          const alphabet = node.getAttributeNS(NS2.SSML, "alphabet") || inheritedAlphabet;
          if (!el) {
            const ph = node.getAttributeNS(NS2.SSML, "ph");
            if (ph) {
              el = ssml.createElementNS(NS2.SSML, "phoneme");
              if (alphabet) el.setAttribute("alphabet", alphabet);
              el.setAttribute("ph", ph);
            }
          }
          if (!el) el = parent;
          let child = node.firstChild;
          while (child) {
            const childEl = convert(child, el, alphabet);
            if (childEl && el !== childEl) el.append(childEl);
            child = child.nextSibling;
          }
          return el;
        };
        convert(fragment.firstChild, ssml.documentElement, inherited.alphabet);
        return ssml;
      };
      getFragmentWithMarks = (range, textWalker2, granularity) => {
        const lang = getLang(range.commonAncestorContainer);
        const alphabet = getAlphabet(range.commonAncestorContainer);
        const segmenter = getSegmenter(lang, granularity);
        const fragment = range.cloneContents();
        const entries = [...textWalker2(range, segmenter)];
        const fragmentEntries = [...textWalker2(fragment, segmenter)];
        for (const [name, range2] of fragmentEntries) {
          const mark = document.createElement("foliate-mark");
          mark.dataset.name = name;
          range2.insertNode(mark);
        }
        const ssml = fragmentToSSML(fragment, { lang, alphabet });
        return { entries, ssml };
      };
      rangeIsEmpty = (range) => !range.toString().trim();
      ListIterator = class {
        #arr = [];
        #iter;
        #index = -1;
        #f;
        constructor(iter, f3 = (x3) => x3) {
          this.#iter = iter;
          this.#f = f3;
        }
        current() {
          if (this.#arr[this.#index]) return this.#f(this.#arr[this.#index]);
        }
        first() {
          const newIndex = 0;
          if (this.#arr[newIndex]) {
            this.#index = newIndex;
            return this.#f(this.#arr[newIndex]);
          }
        }
        prev() {
          const newIndex = this.#index - 1;
          if (this.#arr[newIndex]) {
            this.#index = newIndex;
            return this.#f(this.#arr[newIndex]);
          }
        }
        next() {
          const newIndex = this.#index + 1;
          if (this.#arr[newIndex]) {
            this.#index = newIndex;
            return this.#f(this.#arr[newIndex]);
          }
          while (true) {
            const { done, value } = this.#iter.next();
            if (done) break;
            this.#arr.push(value);
            if (this.#arr[newIndex]) {
              this.#index = newIndex;
              return this.#f(this.#arr[newIndex]);
            }
          }
        }
        find(f3) {
          const index = this.#arr.findIndex((x3) => f3(x3));
          if (index > -1) {
            this.#index = index;
            return this.#f(this.#arr[index]);
          }
          while (true) {
            const { done, value } = this.#iter.next();
            if (done) break;
            this.#arr.push(value);
            if (f3(value)) {
              this.#index = this.#arr.length - 1;
              return this.#f(value);
            }
          }
        }
      };
      TTS = class {
        #list;
        #ranges;
        #lastMark;
        #serializer = new XMLSerializer();
        constructor(doc, textWalker2, highlight, granularity) {
          this.doc = doc;
          this.highlight = highlight;
          this.#list = new ListIterator(getBlocks(doc), (range) => {
            const { entries, ssml } = getFragmentWithMarks(range, textWalker2, granularity);
            this.#ranges = new Map(entries);
            return [ssml, range];
          });
        }
        #getMarkElement(doc, mark) {
          if (!mark) return null;
          return doc.querySelector(`mark[name="${CSS.escape(mark)}"`);
        }
        #speak(doc, getNode) {
          if (!doc) return;
          if (!getNode) return this.#serializer.serializeToString(doc);
          const ssml = document.implementation.createDocument(NS2.SSML, "speak");
          ssml.documentElement.replaceWith(ssml.importNode(doc.documentElement, true));
          let node = getNode(ssml)?.previousSibling;
          while (node) {
            const next = node.previousSibling ?? node.parentNode?.previousSibling;
            node.parentNode.removeChild(node);
            node = next;
          }
          return this.#serializer.serializeToString(ssml);
        }
        start() {
          this.#lastMark = null;
          const [doc] = this.#list.first() ?? [];
          if (!doc) return this.next();
          return this.#speak(doc, (ssml) => this.#getMarkElement(ssml, this.#lastMark));
        }
        resume() {
          const [doc] = this.#list.current() ?? [];
          if (!doc) return this.next();
          return this.#speak(doc, (ssml) => this.#getMarkElement(ssml, this.#lastMark));
        }
        prev(paused) {
          this.#lastMark = null;
          const [doc, range] = this.#list.prev() ?? [];
          if (paused && range) this.highlight(range.cloneRange());
          return this.#speak(doc);
        }
        next(paused) {
          this.#lastMark = null;
          const [doc, range] = this.#list.next() ?? [];
          if (paused && range) this.highlight(range.cloneRange());
          return this.#speak(doc);
        }
        from(range) {
          this.#lastMark = null;
          const [doc] = this.#list.find((range_) => range.compareBoundaryPoints(Range.END_TO_START, range_) <= 0);
          let mark;
          for (const [name, range_] of this.#ranges.entries())
            if (range.compareBoundaryPoints(Range.START_TO_START, range_) <= 0) {
              mark = name;
              break;
            }
          return this.#speak(doc, (ssml) => this.#getMarkElement(ssml, mark));
        }
        setMark(mark) {
          const range = this.#ranges.get(mark);
          if (range) {
            this.#lastMark = mark;
            this.highlight(range.cloneRange());
          }
        }
      };
    }
  });

  // view.js
  init_epubcfi();

  // progress.js
  var assignIDs = (toc) => {
    let id = 0;
    const assignID = (item) => {
      item.id = id++;
      if (item.subitems) for (const subitem of item.subitems) assignID(subitem);
    };
    for (const item of toc) assignID(item);
    return toc;
  };
  var flatten = (items) => items.map((item) => item.subitems?.length ? [item, flatten(item.subitems)].flat() : item).flat();
  var TOCProgress = class {
    async init({ toc, ids, splitHref, getFragment }) {
      assignIDs(toc);
      const items = flatten(toc);
      const grouped = /* @__PURE__ */ new Map();
      for (const [i3, item] of items.entries()) {
        const [id, fragment] = await splitHref(item?.href) ?? [];
        const value = { fragment, item };
        if (grouped.has(id)) grouped.get(id).items.push(value);
        else grouped.set(id, { prev: items[i3 - 1], items: [value] });
      }
      const map = /* @__PURE__ */ new Map();
      for (const [i3, id] of ids.entries()) {
        if (grouped.has(id)) map.set(id, grouped.get(id));
        else map.set(id, map.get(ids[i3 - 1]));
      }
      this.ids = ids;
      this.map = map;
      this.getFragment = getFragment;
    }
    getProgress(index, range) {
      if (!this.ids) return;
      const id = this.ids[index];
      const obj = this.map.get(id);
      if (!obj) return null;
      const { prev, items } = obj;
      if (!items) return prev;
      if (!range || items.length === 1 && !items[0].fragment) return items[0].item;
      const doc = range.startContainer.getRootNode();
      for (const [i3, { fragment }] of items.entries()) {
        const el = this.getFragment(doc, fragment);
        if (!el) continue;
        if (range.comparePoint(el, 0) > 0)
          return items[i3 - 1]?.item ?? prev;
      }
      return items[items.length - 1].item;
    }
  };
  var SectionProgress = class {
    constructor(sections, sizePerLoc, sizePerTimeUnit) {
      this.sizes = sections.map((s3) => s3.linear != "no" && s3.size > 0 ? s3.size : 0);
      this.sizePerLoc = sizePerLoc;
      this.sizePerTimeUnit = sizePerTimeUnit;
      this.sizeTotal = this.sizes.reduce((a3, b3) => a3 + b3, 0);
      this.sectionFractions = this.#getSectionFractions();
    }
    #getSectionFractions() {
      const { sizeTotal } = this;
      const results = [0];
      let sum = 0;
      for (const size of this.sizes) results.push((sum += size) / sizeTotal);
      return results;
    }
    // get progress given index of and fractions within a section
    getProgress(index, fractionInSection, pageFraction = 0) {
      const { sizes, sizePerLoc, sizePerTimeUnit, sizeTotal } = this;
      const sizeInSection = sizes[index] ?? 0;
      const sizeBefore = sizes.slice(0, index).reduce((a3, b3) => a3 + b3, 0);
      const size = sizeBefore + fractionInSection * sizeInSection;
      const nextSize = size + pageFraction * sizeInSection;
      const remainingTotal = sizeTotal - size;
      const remainingSection = (1 - fractionInSection) * sizeInSection;
      return {
        fraction: nextSize / sizeTotal,
        section: {
          current: index,
          total: sizes.length
        },
        location: {
          current: Math.floor(size / sizePerLoc),
          next: Math.floor(nextSize / sizePerLoc),
          total: Math.ceil(sizeTotal / sizePerLoc)
        },
        time: {
          section: remainingSection / sizePerTimeUnit,
          total: remainingTotal / sizePerTimeUnit
        }
      };
    }
    // the inverse of `getProgress`
    // get index of and fraction in section based on total fraction
    getSection(fraction) {
      if (fraction <= 0) return [0, 0];
      if (fraction >= 1) return [this.sizes.length - 1, 1];
      fraction = fraction + Number.EPSILON;
      const { sizeTotal } = this;
      let index = this.sectionFractions.findIndex((x3) => x3 > fraction) - 1;
      if (index < 0) return [0, 0];
      while (!this.sizes[index]) index++;
      const fractionInSection = (fraction - this.sectionFractions[index]) / (this.sizes[index] / sizeTotal);
      return [index, fractionInSection];
    }
  };

  // overlayer.js
  var createSVGElement = (tag) => document.createElementNS("http://www.w3.org/2000/svg", tag);
  var Overlayer = class {
    #svg = createSVGElement("svg");
    #map = /* @__PURE__ */ new Map();
    constructor() {
      Object.assign(this.#svg.style, {
        position: "absolute",
        top: "0",
        left: "0",
        width: "100%",
        height: "100%",
        pointerEvents: "none"
      });
    }
    get element() {
      return this.#svg;
    }
    add(key, range, draw, options) {
      if (this.#map.has(key)) this.remove(key);
      if (typeof range === "function") range = range(this.#svg.getRootNode());
      const rects = range.getClientRects();
      const element = draw(rects, options);
      this.#svg.append(element);
      this.#map.set(key, { range, draw, options, element, rects });
    }
    remove(key) {
      if (!this.#map.has(key)) return;
      this.#svg.removeChild(this.#map.get(key).element);
      this.#map.delete(key);
    }
    redraw() {
      for (const obj of this.#map.values()) {
        const { range, draw, options, element } = obj;
        this.#svg.removeChild(element);
        const rects = range.getClientRects();
        const el = draw(rects, options);
        this.#svg.append(el);
        obj.element = el;
        obj.rects = rects;
      }
    }
    hitTest({ x: x3, y: y3 }) {
      const arr = Array.from(this.#map.entries());
      for (let i3 = arr.length - 1; i3 >= 0; i3--) {
        const [key, obj] = arr[i3];
        for (const { left, top, right, bottom } of obj.rects)
          if (top <= y3 && left <= x3 && bottom > y3 && right > x3)
            return [key, obj.range];
      }
      return [];
    }
    // Bug #287 / GH #1268: tolerant variant for AZW3/Foliate highlight taps.
    // Mirrors the Swift `HighlightHitTolerance`: each annotation rect is
    // expanded per-side toward Apple's 44pt minimum touch target
    // (slop = max(0, (44 - dim) / 2), so a rect already ≥ 44pt gets none), and
    // on overlap the nearest-center rect wins. Lets a near-miss tap open the
    // highlight popover instead of falling through to a page-turn. Used as a
    // fallback ONLY after the exact `hitTest` misses, so exact behavior is
    // unchanged.
    hitTestWithTolerance({ x: x3, y: y3 }, minTarget = 44, skipPrefix = null) {
      const arr = Array.from(this.#map.entries());
      let best = null;
      for (let i3 = arr.length - 1; i3 >= 0; i3--) {
        const [key, obj] = arr[i3];
        if (skipPrefix && typeof key === "string" && key.startsWith(skipPrefix))
          continue;
        for (const { left, top, right, bottom } of obj.rects) {
          const w2 = right - left;
          const h3 = bottom - top;
          if (w2 <= 0 || h3 <= 0) continue;
          const sx = Math.max(0, (minTarget - w2) / 2);
          const sy = Math.max(0, (minTarget - h3) / 2);
          if (left - sx <= x3 && x3 <= right + sx && top - sy <= y3 && y3 <= bottom + sy) {
            const cx = (left + right) / 2;
            const cy = (top + bottom) / 2;
            const dist = (x3 - cx) * (x3 - cx) + (y3 - cy) * (y3 - cy);
            if (best === null || dist < best.dist)
              best = { key, range: obj.range, dist };
          }
        }
      }
      return best === null ? [] : [best.key, best.range];
    }
    static underline(rects, options = {}) {
      const { color = "red", width: strokeWidth = 2, writingMode } = options;
      const g3 = createSVGElement("g");
      g3.setAttribute("fill", color);
      if (writingMode === "vertical-rl" || writingMode === "vertical-lr")
        for (const { right, top, height } of rects) {
          const el = createSVGElement("rect");
          el.setAttribute("x", right - strokeWidth);
          el.setAttribute("y", top);
          el.setAttribute("height", height);
          el.setAttribute("width", strokeWidth);
          g3.append(el);
        }
      else for (const { left, bottom, width } of rects) {
        const el = createSVGElement("rect");
        el.setAttribute("x", left);
        el.setAttribute("y", bottom - strokeWidth);
        el.setAttribute("height", strokeWidth);
        el.setAttribute("width", width);
        g3.append(el);
      }
      return g3;
    }
    static strikethrough(rects, options = {}) {
      const { color = "red", width: strokeWidth = 2, writingMode } = options;
      const g3 = createSVGElement("g");
      g3.setAttribute("fill", color);
      if (writingMode === "vertical-rl" || writingMode === "vertical-lr")
        for (const { right, left, top, height } of rects) {
          const el = createSVGElement("rect");
          el.setAttribute("x", (right + left) / 2);
          el.setAttribute("y", top);
          el.setAttribute("height", height);
          el.setAttribute("width", strokeWidth);
          g3.append(el);
        }
      else for (const { left, top, bottom, width } of rects) {
        const el = createSVGElement("rect");
        el.setAttribute("x", left);
        el.setAttribute("y", (top + bottom) / 2);
        el.setAttribute("height", strokeWidth);
        el.setAttribute("width", width);
        g3.append(el);
      }
      return g3;
    }
    static squiggly(rects, options = {}) {
      const { color = "red", width: strokeWidth = 2, writingMode } = options;
      const g3 = createSVGElement("g");
      g3.setAttribute("fill", "none");
      g3.setAttribute("stroke", color);
      g3.setAttribute("stroke-width", strokeWidth);
      const block = strokeWidth * 1.5;
      if (writingMode === "vertical-rl" || writingMode === "vertical-lr")
        for (const { right, top, height } of rects) {
          const el = createSVGElement("path");
          const n3 = Math.round(height / block / 1.5);
          const inline = height / n3;
          const ls = Array.from(
            { length: n3 },
            (_2, i3) => `l${i3 % 2 ? -block : block} ${inline}`
          ).join("");
          el.setAttribute("d", `M${right} ${top}${ls}`);
          g3.append(el);
        }
      else for (const { left, bottom, width } of rects) {
        const el = createSVGElement("path");
        const n3 = Math.round(width / block / 1.5);
        const inline = width / n3;
        const ls = Array.from(
          { length: n3 },
          (_2, i3) => `l${inline} ${i3 % 2 ? block : -block}`
        ).join("");
        el.setAttribute("d", `M${left} ${bottom}${ls}`);
        g3.append(el);
      }
      return g3;
    }
    static highlight(rects, options = {}) {
      const { color = "red" } = options;
      const g3 = createSVGElement("g");
      g3.setAttribute("fill", color);
      g3.style.opacity = "var(--overlayer-highlight-opacity, .3)";
      g3.style.mixBlendMode = "var(--overlayer-highlight-blend-mode, normal)";
      for (const { left, top, height, width } of rects) {
        const el = createSVGElement("rect");
        el.setAttribute("x", left);
        el.setAttribute("y", top);
        el.setAttribute("height", height);
        el.setAttribute("width", width);
        g3.append(el);
      }
      return g3;
    }
    static outline(rects, options = {}) {
      const { color = "red", width: strokeWidth = 3, radius = 3 } = options;
      const g3 = createSVGElement("g");
      g3.setAttribute("fill", "none");
      g3.setAttribute("stroke", color);
      g3.setAttribute("stroke-width", strokeWidth);
      for (const { left, top, height, width } of rects) {
        const el = createSVGElement("rect");
        el.setAttribute("x", left);
        el.setAttribute("y", top);
        el.setAttribute("height", height);
        el.setAttribute("width", width);
        el.setAttribute("rx", radius);
        g3.append(el);
      }
      return g3;
    }
    // make an exact copy of an image in the overlay
    // one can then apply filters to the entire element, without affecting them;
    // it's a bit silly and probably better to just invert images twice
    // (though the color will be off in that case if you do heu-rotate)
    static copyImage([rect], options = {}) {
      const { src } = options;
      const image = createSVGElement("image");
      const { left, top, height, width } = rect;
      image.setAttribute("href", src);
      image.setAttribute("x", left);
      image.setAttribute("y", top);
      image.setAttribute("height", height);
      image.setAttribute("width", width);
      return image;
    }
  };

  // text-walker.js
  var walkRange = (range, walker) => {
    const nodes = [];
    for (let node = walker.currentNode; node; node = walker.nextNode()) {
      const compare = range.comparePoint(node, 0);
      if (compare === 0) nodes.push(node);
      else if (compare > 0) break;
    }
    return nodes;
  };
  var walkDocument = (_2, walker) => {
    const nodes = [];
    for (let node = walker.nextNode(); node; node = walker.nextNode())
      nodes.push(node);
    return nodes;
  };
  var filter = NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT | NodeFilter.SHOW_CDATA_SECTION;
  var acceptNode = (node) => {
    if (node.nodeType === 1) {
      const name = node.tagName.toLowerCase();
      if (name === "script" || name === "style") return NodeFilter.FILTER_REJECT;
      return NodeFilter.FILTER_SKIP;
    }
    return NodeFilter.FILTER_ACCEPT;
  };
  var textWalker = function* (x3, func, filterFunc) {
    const root = x3.commonAncestorContainer ?? x3.body ?? x3;
    const walker = document.createTreeWalker(root, filter, { acceptNode: filterFunc || acceptNode });
    const walk = x3.commonAncestorContainer ? walkRange : walkDocument;
    const nodes = walk(x3, walker);
    const strs = nodes.map((node) => node.nodeValue);
    const makeRange2 = (startIndex, startOffset, endIndex, endOffset) => {
      const range = document.createRange();
      range.setStart(nodes[startIndex], startOffset);
      range.setEnd(nodes[endIndex], endOffset);
      return range;
    };
    for (const match of func(strs, makeRange2)) yield match;
  };

  // view.js
  var SEARCH_PREFIX = "foliate-search:";
  var isZip = async (file) => {
    const arr = new Uint8Array(await file.slice(0, 4).arrayBuffer());
    return arr[0] === 80 && arr[1] === 75 && arr[2] === 3 && arr[3] === 4;
  };
  var isPDF = async (file) => {
    const arr = new Uint8Array(await file.slice(0, 5).arrayBuffer());
    return arr[0] === 37 && arr[1] === 80 && arr[2] === 68 && arr[3] === 70 && arr[4] === 45;
  };
  var isCBZ = ({ name, type }) => type === "application/vnd.comicbook+zip" || name.endsWith(".cbz");
  var isFB2 = ({ name, type }) => type === "application/x-fictionbook+xml" || name.endsWith(".fb2");
  var isFBZ = ({ name, type }) => type === "application/x-zip-compressed-fb2" || name.endsWith(".fb2.zip") || name.endsWith(".fbz");
  var makeZipLoader = async (file) => {
    const { configure, ZipReader, BlobReader, TextWriter, BlobWriter } = await Promise.resolve().then(() => (init_zip(), zip_exports));
    configure({ useWebWorkers: false });
    const reader = new ZipReader(new BlobReader(file));
    const entries = await reader.getEntries();
    const map = new Map(entries.map((entry) => [entry.filename, entry]));
    const load = (f3) => (name, ...args) => map.has(name) ? f3(map.get(name), ...args) : null;
    const loadText = load((entry) => entry.getData(new TextWriter()));
    const loadBlob = load((entry, type) => entry.getData(new BlobWriter(type)));
    const getSize = (name) => map.get(name)?.uncompressedSize ?? 0;
    return { entries, loadText, loadBlob, getSize };
  };
  var getFileEntries = async (entry) => entry.isFile ? entry : (await Promise.all(Array.from(
    await new Promise((resolve, reject) => entry.createReader().readEntries((entries) => resolve(entries), (error) => reject(error))),
    getFileEntries
  ))).flat();
  var makeDirectoryLoader = async (entry) => {
    const entries = await getFileEntries(entry);
    const files = await Promise.all(
      entries.map((entry2) => new Promise((resolve, reject) => entry2.file(
        (file) => resolve([file, entry2.fullPath]),
        (error) => reject(error)
      )))
    );
    const map = new Map(files.map(([file, path]) => [path.replace(entry.fullPath + "/", ""), file]));
    const decoder2 = new TextDecoder();
    const decode = (x3) => x3 ? decoder2.decode(x3) : null;
    const getBuffer = (name) => map.get(name)?.arrayBuffer() ?? null;
    const loadText = async (name) => decode(await getBuffer(name));
    const loadBlob = (name) => map.get(name);
    const getSize = (name) => map.get(name)?.size ?? 0;
    return { loadText, loadBlob, getSize };
  };
  var ResponseError = class extends Error {
  };
  var NotFoundError = class extends Error {
  };
  var UnsupportedTypeError = class extends Error {
  };
  var fetchFile = async (url) => {
    const res = await fetch(url);
    if (!res.ok) throw new ResponseError(
      `${res.status} ${res.statusText}`,
      { cause: res }
    );
    return new File([await res.blob()], new URL(res.url).pathname);
  };
  var makeBook = async (file) => {
    if (typeof file === "string") file = await fetchFile(file);
    let book;
    if (file.isDirectory) {
      const loader = await makeDirectoryLoader(file);
      const { EPUB: EPUB2 } = await Promise.resolve().then(() => (init_epub(), epub_exports));
      book = await new EPUB2(loader).init();
    } else if (!file.size) throw new NotFoundError("File not found");
    else if (await isZip(file)) {
      const loader = await makeZipLoader(file);
      if (isCBZ(file)) {
        const { makeComicBook: makeComicBook2 } = await Promise.resolve().then(() => (init_comic_book(), comic_book_exports));
        book = makeComicBook2(loader, file);
      } else if (isFBZ(file)) {
        const { makeFB2: makeFB22 } = await Promise.resolve().then(() => (init_fb2(), fb2_exports));
        const { entries } = loader;
        const entry = entries.find((entry2) => entry2.filename.endsWith(".fb2"));
        const blob = await loader.loadBlob((entry ?? entries[0]).filename);
        book = await makeFB22(blob);
      } else {
        const { EPUB: EPUB2 } = await Promise.resolve().then(() => (init_epub(), epub_exports));
        book = await new EPUB2(loader).init();
      }
    } else if (await isPDF(file)) {
      const { makePDF: makePDF2 } = await Promise.resolve().then(() => (init_pdf(), pdf_exports));
      book = await makePDF2(file);
    } else {
      const { isMOBI: isMOBI2, MOBI: MOBI2 } = await Promise.resolve().then(() => (init_mobi(), mobi_exports));
      if (await isMOBI2(file)) {
        const fflate = await Promise.resolve().then(() => (init_fflate(), fflate_exports));
        book = await new MOBI2({ unzlib: fflate.unzlibSync }).open(file);
      } else if (isFB2(file)) {
        const { makeFB2: makeFB22 } = await Promise.resolve().then(() => (init_fb2(), fb2_exports));
        book = await makeFB22(file);
      }
    }
    if (!book) throw new UnsupportedTypeError("File type not supported");
    return book;
  };
  var CursorAutohider = class _CursorAutohider {
    #timeout;
    #el;
    #check;
    #state;
    constructor(el, check, state = {}) {
      this.#el = el;
      this.#check = check;
      this.#state = state;
      if (this.#state.hidden) this.hide();
      this.#el.addEventListener("mousemove", ({ screenX, screenY }) => {
        if (screenX === this.#state.x && screenY === this.#state.y) return;
        this.#state.x = screenX, this.#state.y = screenY;
        this.show();
        if (this.#timeout) clearTimeout(this.#timeout);
        if (check()) this.#timeout = setTimeout(this.hide.bind(this), 1e3);
      }, false);
    }
    cloneFor(el) {
      return new _CursorAutohider(el, this.#check, this.#state);
    }
    hide() {
      this.#el.style.cursor = "none";
      this.#state.hidden = true;
    }
    show() {
      this.#el.style.removeProperty("cursor");
      this.#state.hidden = false;
    }
  };
  var History = class extends EventTarget {
    #arr = [];
    #index = -1;
    pushState(x3) {
      const last = this.#arr[this.#index];
      if (last === x3 || last?.fraction && last.fraction === x3.fraction) return;
      this.#arr[++this.#index] = x3;
      this.#arr.length = this.#index + 1;
      this.dispatchEvent(new Event("index-change"));
    }
    replaceState(x3) {
      const index = this.#index;
      this.#arr[index] = x3;
    }
    back() {
      const index = this.#index;
      if (index <= 0) return;
      const detail = { state: this.#arr[index - 1] };
      this.#index = index - 1;
      this.dispatchEvent(new CustomEvent("popstate", { detail }));
      this.dispatchEvent(new Event("index-change"));
    }
    forward() {
      const index = this.#index;
      if (index >= this.#arr.length - 1) return;
      const detail = { state: this.#arr[index + 1] };
      this.#index = index + 1;
      this.dispatchEvent(new CustomEvent("popstate", { detail }));
      this.dispatchEvent(new Event("index-change"));
    }
    get canGoBack() {
      return this.#index > 0;
    }
    get canGoForward() {
      return this.#index < this.#arr.length - 1;
    }
    clear() {
      this.#arr = [];
      this.#index = -1;
    }
  };
  var languageInfo = (lang) => {
    if (!lang) return {};
    try {
      const canonical = Intl.getCanonicalLocales(lang)[0];
      const locale = new Intl.Locale(canonical);
      const isCJK = ["zh", "ja", "kr"].includes(locale.language);
      const direction = (locale.getTextInfo?.() ?? locale.textInfo)?.direction;
      return { canonical, locale, isCJK, direction };
    } catch (e3) {
      console.warn(e3);
      return {};
    }
  };
  var View2 = class extends HTMLElement {
    #root = this.attachShadow({ mode: "closed" });
    #sectionProgress;
    #tocProgress;
    #pageProgress;
    #searchResults = /* @__PURE__ */ new Map();
    #cursorAutohider = new CursorAutohider(this, () => this.hasAttribute("autohide-cursor"));
    isFixedLayout = false;
    lastLocation;
    history = new History();
    constructor() {
      super();
      this.history.addEventListener("popstate", ({ detail }) => {
        const resolved = this.resolveNavigation(detail.state);
        this.renderer.goTo(resolved);
      });
    }
    async open(book) {
      if (typeof book === "string" || typeof book.arrayBuffer === "function" || book.isDirectory) book = await makeBook(book);
      this.book = book;
      this.language = languageInfo(book.metadata?.language);
      if (book.splitTOCHref && book.getTOCFragment) {
        const ids = book.sections.map((s3) => s3.id);
        this.#sectionProgress = new SectionProgress(book.sections, 1500, 1600);
        const splitHref = book.splitTOCHref.bind(book);
        const getFragment = book.getTOCFragment.bind(book);
        this.#tocProgress = new TOCProgress();
        await this.#tocProgress.init({
          toc: book.toc ?? [],
          ids,
          splitHref,
          getFragment
        });
        this.#pageProgress = new TOCProgress();
        await this.#pageProgress.init({
          toc: book.pageList ?? [],
          ids,
          splitHref,
          getFragment
        });
      }
      this.isFixedLayout = this.book.rendition?.layout === "pre-paginated";
      if (this.isFixedLayout) {
        await Promise.resolve().then(() => (init_fixed_layout(), fixed_layout_exports));
        this.renderer = document.createElement("foliate-fxl");
      } else {
        await Promise.resolve().then(() => (init_paginator(), paginator_exports));
        this.renderer = document.createElement("foliate-paginator");
      }
      this.renderer.setAttribute("exportparts", "head,foot,filter");
      this.renderer.addEventListener("load", (e3) => this.#onLoad(e3.detail));
      this.renderer.addEventListener("relocate", (e3) => this.#onRelocate(e3.detail));
      this.renderer.addEventListener("create-overlayer", (e3) => e3.detail.attach(this.#createOverlayer(e3.detail)));
      this.renderer.open(book);
      this.#root.append(this.renderer);
      if (book.sections.some((section) => section.mediaOverlay)) {
        const activeClass = book.media.activeClass;
        const playbackActiveClass = book.media.playbackActiveClass;
        this.mediaOverlay = book.getMediaOverlay();
        let lastActive;
        this.mediaOverlay.addEventListener("highlight", (e3) => {
          const resolved = this.resolveNavigation(e3.detail.text);
          this.renderer.goTo(resolved).then(() => {
            const { doc } = this.renderer.getContents().find((x3) => x3.index = resolved.index);
            const el = resolved.anchor(doc);
            el.classList.add(activeClass);
            if (playbackActiveClass) el.ownerDocument.documentElement.classList.add(playbackActiveClass);
            lastActive = new WeakRef(el);
          });
        });
        this.mediaOverlay.addEventListener("unhighlight", () => {
          const el = lastActive?.deref();
          if (el) {
            el.classList.remove(activeClass);
            if (playbackActiveClass) el.ownerDocument.documentElement.classList.remove(playbackActiveClass);
          }
        });
      }
    }
    close() {
      this.renderer?.destroy();
      this.renderer?.remove();
      this.#sectionProgress = null;
      this.#tocProgress = null;
      this.#pageProgress = null;
      this.#searchResults = /* @__PURE__ */ new Map();
      this.lastLocation = null;
      this.history.clear();
      this.tts = null;
      this.mediaOverlay = null;
    }
    goToTextStart() {
      return this.goTo(this.book.landmarks?.find((m3) => m3.type.includes("bodymatter") || m3.type.includes("text"))?.href ?? this.book.sections.findIndex((s3) => s3.linear !== "no"));
    }
    async init({ lastLocation, showTextStart }) {
      const resolved = lastLocation ? this.resolveNavigation(lastLocation) : null;
      if (resolved) {
        await this.renderer.goTo(resolved);
        this.history.pushState(lastLocation);
      } else if (showTextStart) await this.goToTextStart();
      else {
        this.history.pushState(0);
        await this.next();
      }
    }
    #emit(name, detail, cancelable) {
      return this.dispatchEvent(new CustomEvent(name, { detail, cancelable }));
    }
    #onRelocate({ reason, range, index, fraction, size }) {
      const progress = this.#sectionProgress?.getProgress(index, fraction, size) ?? {};
      const tocItem = this.#tocProgress?.getProgress(index, range);
      const pageItem = this.#pageProgress?.getProgress(index, range);
      const cfi = this.getCFI(index, range);
      this.lastLocation = { ...progress, tocItem, pageItem, cfi, range };
      if (reason === "snap" || reason === "page" || reason === "scroll")
        this.history.replaceState(cfi);
      this.#emit("relocate", this.lastLocation);
    }
    #onLoad({ doc, index }) {
      doc.documentElement.lang ||= this.language.canonical ?? "";
      if (!this.language.isCJK)
        doc.documentElement.dir ||= this.language.direction ?? "";
      this.#handleLinks(doc, index);
      this.#cursorAutohider.cloneFor(doc.documentElement);
      this.#emit("load", { doc, index });
    }
    #handleLinks(doc, index) {
      const { book } = this;
      const section = book.sections[index];
      doc.addEventListener("click", (e3) => {
        const a3 = e3.target.closest("a[href]");
        if (!a3) return;
        e3.preventDefault();
        const href_ = a3.getAttribute("href");
        const href = section?.resolveHref?.(href_) ?? href_;
        if (book?.isExternal?.(href))
          Promise.resolve(this.#emit("external-link", { a: a3, href }, true)).then((x3) => x3 ? globalThis.open(href, "_blank") : null).catch((e4) => console.error(e4));
        else Promise.resolve(this.#emit("link", { a: a3, href }, true)).then((x3) => x3 ? this.goTo(href) : null).catch((e4) => console.error(e4));
      });
    }
    async addAnnotation(annotation, remove) {
      const { value } = annotation;
      if (value.startsWith(SEARCH_PREFIX)) {
        const cfi = value.replace(SEARCH_PREFIX, "");
        const { index: index2, anchor: anchor2 } = await this.resolveNavigation(cfi);
        const obj2 = this.#getOverlayer(index2);
        if (obj2) {
          const { overlayer, doc } = obj2;
          if (remove) {
            overlayer.remove(value);
            return;
          }
          const range = doc ? anchor2(doc) : anchor2;
          overlayer.add(value, range, Overlayer.outline);
        }
        return;
      }
      const { index, anchor } = await this.resolveNavigation(value);
      const obj = this.#getOverlayer(index);
      if (obj) {
        const { overlayer, doc } = obj;
        overlayer.remove(value);
        if (!remove) {
          const range = doc ? anchor(doc) : anchor;
          const draw = (func, opts) => overlayer.add(value, range, func, opts);
          this.#emit("draw-annotation", { draw, annotation, doc, range });
        }
      }
      const label = this.#tocProgress.getProgress(index)?.label ?? "";
      return { index, label };
    }
    deleteAnnotation(annotation) {
      return this.addAnnotation(annotation, true);
    }
    #getOverlayer(index) {
      return this.renderer.getContents().find((x3) => x3.index === index && x3.overlayer);
    }
    #createOverlayer({ doc, index }) {
      const overlayer = new Overlayer();
      doc.addEventListener("click", (e3) => {
        let [value, range] = overlayer.hitTest(e3);
        if (!value || value.startsWith(SEARCH_PREFIX)) {
          ;
          [value, range] = overlayer.hitTestWithTolerance(e3, 44, SEARCH_PREFIX);
        }
        if (value && !value.startsWith(SEARCH_PREFIX)) {
          e3.__vreaderAnnotationHit = true;
          this.#emit("show-annotation", { value, index, range });
        }
      }, true);
      const list = this.#searchResults.get(index);
      if (list) for (const item of list) this.addAnnotation(item);
      this.#emit("create-overlay", { index });
      return overlayer;
    }
    async showAnnotation(annotation) {
      const { value } = annotation;
      const resolved = await this.goTo(value);
      if (resolved) {
        const { index, anchor } = resolved;
        const { doc } = this.#getOverlayer(index);
        const range = anchor(doc);
        this.#emit("show-annotation", { value, index, range });
      }
    }
    getCFI(index, range) {
      const baseCFI = this.book.sections[index].cfi ?? fake.fromIndex(index);
      if (!range) return baseCFI;
      return joinIndir(baseCFI, fromRange(range));
    }
    resolveCFI(cfi) {
      if (this.book.resolveCFI)
        return this.book.resolveCFI(cfi);
      else {
        const parts = parse(cfi);
        const index = fake.toIndex((parts.parent ?? parts).shift());
        const anchor = (doc) => toRange(doc, parts);
        return { index, anchor };
      }
    }
    resolveNavigation(target) {
      try {
        if (typeof target === "number") return { index: target };
        if (typeof target.fraction === "number") {
          const [index, anchor] = this.#sectionProgress.getSection(target.fraction);
          return { index, anchor };
        }
        if (isCFI.test(target)) return this.resolveCFI(target);
        return this.book.resolveHref(target);
      } catch (e3) {
        console.error(e3);
        console.error(`Could not resolve target ${target}`);
      }
    }
    async goTo(target) {
      const resolved = this.resolveNavigation(target);
      try {
        await this.renderer.goTo(resolved);
        this.history.pushState(target);
        return resolved;
      } catch (e3) {
        console.error(e3);
        console.error(`Could not go to ${target}`);
      }
    }
    async goToFraction(frac) {
      const [index, anchor] = this.#sectionProgress.getSection(frac);
      await this.renderer.goTo({ index, anchor });
      this.history.pushState({ fraction: frac });
    }
    async select(target) {
      try {
        const obj = await this.resolveNavigation(target);
        await this.renderer.goTo({ ...obj, select: true });
        this.history.pushState(target);
      } catch (e3) {
        console.error(e3);
        console.error(`Could not go to ${target}`);
      }
    }
    deselect() {
      for (const { doc } of this.renderer.getContents())
        doc.defaultView.getSelection().removeAllRanges();
    }
    getSectionFractions() {
      return (this.#sectionProgress?.sectionFractions ?? []).map((x3) => x3 + Number.EPSILON);
    }
    getProgressOf(index, range) {
      const tocItem = this.#tocProgress?.getProgress(index, range);
      const pageItem = this.#pageProgress?.getProgress(index, range);
      return { tocItem, pageItem };
    }
    async getTOCItemOf(target) {
      try {
        const { index, anchor } = await this.resolveNavigation(target);
        const doc = await this.book.sections[index].createDocument();
        const frag = anchor(doc);
        const isRange = frag instanceof Range;
        const range = isRange ? frag : doc.createRange();
        if (!isRange) range.selectNodeContents(frag);
        return this.#tocProgress.getProgress(index, range);
      } catch (e3) {
        console.error(e3);
        console.error(`Could not get ${target}`);
      }
    }
    async prev(distance) {
      await this.renderer.prev(distance);
    }
    async next(distance) {
      await this.renderer.next(distance);
    }
    goLeft() {
      return this.book.dir === "rtl" ? this.next() : this.prev();
    }
    goRight() {
      return this.book.dir === "rtl" ? this.prev() : this.next();
    }
    async *#searchSection(matcher, query, index) {
      const doc = await this.book.sections[index].createDocument();
      for (const { range, excerpt } of matcher(doc, query))
        yield { cfi: this.getCFI(index, range), excerpt };
    }
    async *#searchBook(matcher, query) {
      const { sections } = this.book;
      for (const [index, { createDocument }] of sections.entries()) {
        if (!createDocument) continue;
        const doc = await createDocument();
        const subitems = Array.from(matcher(doc, query), ({ range, excerpt }) => ({ cfi: this.getCFI(index, range), excerpt }));
        const progress = (index + 1) / sections.length;
        yield { progress };
        if (subitems.length) yield { index, subitems };
      }
    }
    async *search(opts) {
      this.clearSearch();
      const { searchMatcher: searchMatcher2 } = await Promise.resolve().then(() => (init_search(), search_exports));
      const { query, index } = opts;
      const matcher = searchMatcher2(
        textWalker,
        { defaultLocale: this.language, ...opts }
      );
      const iter = index != null ? this.#searchSection(matcher, query, index) : this.#searchBook(matcher, query);
      const list = [];
      this.#searchResults.set(index, list);
      for await (const result of iter) {
        if (result.subitems) {
          const list2 = result.subitems.map(({ cfi }) => ({ value: SEARCH_PREFIX + cfi }));
          this.#searchResults.set(result.index, list2);
          for (const item of list2) this.addAnnotation(item);
          yield {
            label: this.#tocProgress.getProgress(result.index)?.label ?? "",
            subitems: result.subitems
          };
        } else {
          if (result.cfi) {
            const item = { value: SEARCH_PREFIX + result.cfi };
            list.push(item);
            this.addAnnotation(item);
          }
          yield result;
        }
      }
      yield "done";
    }
    clearSearch() {
      for (const list of this.#searchResults.values())
        for (const item of list) this.deleteAnnotation(item);
      this.#searchResults.clear();
    }
    async initTTS(granularity = "word", highlight) {
      const doc = this.renderer.getContents()[0].doc;
      if (this.tts && this.tts.doc === doc) return;
      const { TTS: TTS2 } = await Promise.resolve().then(() => (init_tts(), tts_exports));
      this.tts = new TTS2(doc, textWalker, highlight || ((range) => this.renderer.scrollToAnchor(range, true)), granularity);
    }
    startMediaOverlay() {
      const { index } = this.renderer.getContents()[0];
      return this.mediaOverlay.start(index);
    }
  };
  customElements.define("foliate-view", View2);

  // foliate-host.js
  var view = document.getElementById("view");
  function post(name, detail) {
    try {
      window.webkit?.messageHandlers?.[name]?.postMessage(detail ?? {});
    } catch (e3) {
      console.error(`[foliate-host] postMessage "${name}" failed:`, e3);
    }
  }
  function serializeRect(rect) {
    if (!rect) return null;
    return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
  }
  view.addEventListener("relocate", (e3) => {
    const d2 = e3.detail;
    post("relocate", {
      cfi: d2.cfi,
      fraction: d2.fraction,
      sectionIndex: d2.section?.current ?? 0,
      sectionTotal: d2.section?.total ?? 1,
      locationCurrent: d2.location?.current ?? 0,
      locationTotal: d2.location?.total ?? 1,
      tocLabel: d2.tocItem?.label ?? null,
      tocHref: d2.tocItem?.href ?? null,
      timeSection: d2.time?.section ?? null,
      timeTotal: d2.time?.total ?? null
    });
  });
  view.addEventListener("load", (e3) => {
    post("section-load", {
      index: e3.detail.index
    });
  });
  view.addEventListener("create-overlay", (e3) => {
    post("create-overlay", {
      index: e3.detail.index
    });
  });
  view.addEventListener("draw-annotation", (e3) => {
    const { draw, annotation, doc, range } = e3.detail;
    const value = annotation.value;
    const color = annotation.color || "yellow";
    draw(Overlayer.highlight, { color });
  });
  view.addEventListener("show-annotation", (e3) => {
    post("annotation-show", {
      value: e3.detail.value,
      index: e3.detail.index
    });
  });
  view.addEventListener("external-link", (e3) => {
    e3.preventDefault();
    post("external-link", { href: e3.detail.href });
  });
  {
    let selectionTimeout = null;
    const handleSelection = (sourceDoc) => {
      clearTimeout(selectionTimeout);
      selectionTimeout = setTimeout(() => {
        const contents = view.renderer?.getContents?.();
        if (!contents?.length) return;
        const hasLiveSel = (c2) => {
          const s3 = c2?.doc?.getSelection?.();
          return s3 && !s3.isCollapsed && s3.rangeCount;
        };
        let owner = sourceDoc ? contents.find((c2) => c2.doc === sourceDoc) : null;
        if (!owner || !hasLiveSel(owner)) owner = contents.find(hasLiveSel);
        if (!owner) {
          post("selection", { collapsed: true });
          return;
        }
        const { doc, index } = owner;
        const sel = doc.getSelection();
        if (!sel || sel.isCollapsed || !sel.rangeCount) {
          post("selection", { collapsed: true });
          return;
        }
        const range = sel.getRangeAt(0);
        const text = sel.toString().trim();
        if (!text) return;
        const cfi = view.getCFI(index, range);
        const rect = range.getBoundingClientRect();
        post("selection", {
          collapsed: false,
          text,
          cfi,
          index,
          rect: serializeRect(rect)
        });
      }, 300);
    };
    view.addEventListener("load", (e3) => {
      const doc = e3.detail.doc;
      doc.addEventListener("selectionchange", () => handleSelection(doc));
    });
  }
  view.addEventListener("load", (e3) => {
    const doc = e3.detail.doc;
    doc.addEventListener("click", (event) => {
      if (event.__vreaderAnnotationHit) return;
      if (event.target.closest("a[href]")) return;
      const sel = doc.getSelection();
      if (sel && !sel.isCollapsed) return;
      const x3 = typeof event.clientX === "number" ? event.clientX : null;
      if (x3 === null || !isFinite(x3)) {
        post("tap", {});
        return;
      }
      const mapped = mapTapToHostViewport(doc, x3);
      if (!mapped) {
        post("tap", {});
        return;
      }
      post("tap", { x: mapped.x, w: mapped.w });
    });
  });
  function mapTapToHostViewport(doc, clientX) {
    try {
      const docWin = doc.defaultView;
      const frameEl = docWin && docWin.frameElement;
      if (!frameEl) {
        const w2 = doc.documentElement?.clientWidth || docWin && docWin.innerWidth || 0;
        if (!isFinite(w2) || w2 <= 0) return null;
        return { x: clientX, w: w2 };
      }
      const frameLeft = frameEl.getBoundingClientRect().left;
      const hostWin = frameEl.ownerDocument && frameEl.ownerDocument.defaultView;
      const hostW = hostWin && hostWin.innerWidth;
      if (!isFinite(frameLeft) || !isFinite(hostW) || hostW <= 0) return null;
      return { x: clientX + frameLeft, w: hostW };
    } catch (e3) {
      return null;
    }
  }
  var bookReady = false;
  var currentBook = null;
  window.readerAPI = {
    // Open a book from URL (fetched by Foliate-js)
    async open(url) {
      try {
        await view.open(url);
        bookReady = true;
        currentBook = view.book;
        const meta = currentBook.metadata ?? {};
        const toc = currentBook.toc ?? [];
        post("book-ready", {
          title: meta.title ?? "",
          author: typeof meta.author === "string" ? meta.author : meta.author?.join?.(", ") ?? "",
          language: meta.language ?? "",
          toc: serializeTOC(toc),
          sections: currentBook.sections?.length ?? 0,
          layout: currentBook.rendition?.layout ?? "reflowable"
        });
      } catch (e3) {
        post("error", {
          message: e3.message ?? String(e3),
          type: e3.constructor?.name ?? "Error"
        });
      }
    },
    // Initialize with saved position
    init(opts) {
      if (!opts) return view.init({});
      if (opts.cfi) return view.init({ lastLocation: opts.cfi });
      if (opts.fraction != null) return view.goToFraction(opts.fraction);
      return view.init({});
    },
    // Navigation
    next() {
      view.next();
    },
    prev() {
      view.prev();
    },
    goLeft() {
      view.goLeft();
    },
    goRight() {
      view.goRight();
    },
    goTo(target) {
      view.goTo(target);
    },
    goToFraction(f3) {
      view.goToFraction(f3);
    },
    // Annotations
    addAnnotation(annotation) {
      view.addAnnotation(annotation);
    },
    deleteAnnotation(annotation) {
      view.deleteAnnotation(annotation);
    },
    showAnnotation(annotation) {
      view.showAnnotation(annotation);
    },
    // Selection
    deselect() {
      view.deselect();
    },
    // Search (async generator → posts results)
    async search(opts) {
      try {
        for await (const result of view.search(opts)) {
          if (result === "done") {
            post("search-done", {});
            break;
          }
          if (result.progress != null) {
            post("search-progress", { progress: result.progress });
          } else {
            post("search-result", result);
          }
        }
      } catch (e3) {
        post("error", { message: `Search failed: ${e3.message}` });
      }
    },
    clearSearch() {
      view.clearSearch();
    },
    // TTS
    async initTTS(granularity) {
      view.initTTS(granularity ?? "word", (range) => {
        view.renderer.scrollToAnchor(range);
      });
    },
    tts: {
      start() {
        const ssml = view.tts?.start?.();
        if (ssml) post("tts-ssml", { ssml });
        return ssml;
      },
      next() {
        const ssml = view.tts?.next?.();
        if (ssml) post("tts-ssml", { ssml });
        return ssml;
      },
      prev() {
        const ssml = view.tts?.prev?.();
        if (ssml) post("tts-ssml", { ssml });
        return ssml;
      },
      setMark(mark) {
        view.tts?.setMark?.(mark);
      }
    },
    // Theme / Layout
    setStyles(css) {
      view.renderer?.setStyles?.(css);
    },
    setLayout(opts) {
      const r3 = view.renderer;
      if (!r3) return;
      if (opts.flow) r3.setAttribute("flow", opts.flow);
      if (opts.margin != null) r3.setAttribute("margin", String(opts.margin));
      if (opts.gap != null) r3.setAttribute("gap", String(opts.gap));
      if (opts.maxInlineSize != null) r3.setAttribute("max-inline-size", String(opts.maxInlineSize));
      if (opts.maxBlockSize != null) r3.setAttribute("max-block-size", String(opts.maxBlockSize));
      if (opts.maxColumnCount != null) r3.setAttribute("max-column-count", String(opts.maxColumnCount));
    },
    // Feature #57: whole-book plain-text extraction for TTS.
    // Walks `currentBook.sections` (the same pattern view.search()'s
    // `#searchBook` uses), builds an off-screen Document per section
    // via `createDocument()`, and concatenates the body text. Runs on
    // the host page where `currentBook` is in scope — no shadow-root
    // or iframe traversal. Returns a Promise<string> that
    // evaluateJavaScript is expected to resolve to a Swift String.
    // A section that fails to parse is skipped (partial text is
    // better than no TTS); a book with no sections returns ''.
    async extractPlainText() {
      if (!bookReady || !currentBook?.sections) return "";
      const parts = [];
      for (const section of currentBook.sections) {
        if (typeof section.createDocument !== "function") continue;
        try {
          const doc = await section.createDocument();
          const text = (doc?.body?.textContent ?? "").trim();
          if (text) parts.push(text);
        } catch (e3) {
          console.warn("[foliate-host] extractPlainText section failed:", e3);
        }
      }
      return parts.join("\n\n");
    },
    // Feature #56 WI-11: per-section ordered identifiers for the
    // bilingual translation cache. The unit identifier is the
    // section's index (stringified). A stable index per render is
    // sufficient — Foliate's `view.book.sections` ordering matches
    // the rendered section order; the cache row is keyed by the
    // book's fingerprintKey + this index + the prompt version, so a
    // book reopen looks up the same cached chapter translations.
    async bilingualSectionIDs() {
      if (!bookReady || !currentBook?.sections) return [];
      const ids = [];
      for (let i3 = 0; i3 < currentBook.sections.length; i3++) {
        const s3 = currentBook.sections[i3];
        if (typeof s3?.createDocument !== "function") continue;
        ids.push(String(i3));
      }
      return ids;
    },
    // Feature #56 WI-11: per-section source text for the bilingual
    // translation pipeline. Mirrors `extractPlainText`'s
    // `createDocument()` walk but for a single section, so the
    // `FoliateChapterTextProvider` actor can fetch one unit at a
    // time without re-walking the whole book.
    //
    // `unitID` is the stringified section index (matches what
    // `bilingualSectionIDs` returns). Returns '' on any failure
    // (missing section, parse error, empty body) — translation is
    // a decoration, partial text is the right failure mode.
    async bilingualSectionText(unitID) {
      if (!bookReady || !currentBook?.sections) return "";
      const idx = parseInt(unitID, 10);
      if (isNaN(idx) || idx < 0 || idx >= currentBook.sections.length) {
        return "";
      }
      const s3 = currentBook.sections[idx];
      if (typeof s3?.createDocument !== "function") return "";
      try {
        const doc = await s3.createDocument();
        return (doc?.body?.textContent ?? "").trim();
      } catch (e3) {
        console.warn("[foliate-host] bilingualSectionText section failed:", e3);
        return "";
      }
    },
    // Feature #56 WI-11: walk a specific section's rendered DOM,
    // stamp a stable `data-vreader-bid` attribute on each
    // translatable block (`p` / `li` / `blockquote` / `pre` / `dd`
    // / `dt` — same set the EPUB renderer enumerates), and post
    // an ordered `[{bid, text, sectionIndex}]` payload back to
    // Swift via the `bilingualEnumerate` channel.
    //
    // Gate-4 audit finding H2: in paginated mode foliate-js can
    // keep multiple section docs loaded simultaneously
    // (`view.renderer.getContents()` returns `[{doc, index}]`
    // for every retained section). Walking them all and posting
    // one flat block list would let one unit's translation map
    // spill into adjacent sections. We therefore (a) tag every
    // emitted block with its section's `index`, and (b) accept
    // an optional `targetSectionIndex` so the caller can scope
    // the enumerate to one section. When omitted, every loaded
    // section is enumerated and the Swift pipeline partitions
    // by the per-block `sectionIndex`.
    //
    // The rendered DOM lives inside the section's iframe / shadow
    // root, reachable only via `view.renderer.getContents()`. A
    // re-enumerate after inject keeps existing `data-vreader-bid`
    // values (idempotent stamp) so a section re-render does not
    // shift the cache-key mapping. Decoration siblings carrying
    // `data-vreader-decoration` are skipped so a re-enumerate
    // never stamps a translation block.
    //
    // Gate-4 audit finding M2: an existing
    // `data-vreader-bid` from third-party book HTML cannot be
    // trusted — a hostile attribute value would break the
    // attribute-selector lookup in `bilingualInject` and abort
    // the whole pass. We re-stamp any pre-existing bid whose
    // value does not match the trusted `^fb\d+$` shape so the
    // selector is always over content we wrote.
    bilingualEnumerate(targetSectionIndex) {
      const reqIdx = targetSectionIndex == null ? null : targetSectionIndex;
      try {
        const contents = view.renderer?.getContents?.();
        if (!Array.isArray(contents) || contents.length === 0) {
          post("bilingualEnumerate", {
            requestedSectionIndex: reqIdx,
            blocks: []
          });
          return;
        }
        const BLOCK_TAGS = {
          p: 1,
          li: 1,
          blockquote: 1,
          pre: 1,
          dd: 1,
          dt: 1
        };
        const BLOCK_SELECTOR = Object.keys(BLOCK_TAGS).join(",");
        const TRUSTED_BID = /^fb\d+$/;
        const out = [];
        for (const entry of contents) {
          const doc = entry?.doc;
          if (!doc) continue;
          const sectionIndex = typeof entry.index === "number" ? entry.index : -1;
          if (targetSectionIndex != null && sectionIndex !== targetSectionIndex) {
            continue;
          }
          const all = doc.body ? doc.body.getElementsByTagName("*") : doc.getElementsByTagName("*");
          let seq = doc.__vreaderBilingualSeq ?? 0;
          for (let i3 = 0; i3 < all.length; i3++) {
            const el = all[i3];
            const tag = (el.localName || "").toLowerCase();
            if (!BLOCK_TAGS[tag]) continue;
            if (el.hasAttribute && el.hasAttribute("data-vreader-decoration")) {
              continue;
            }
            if (el.querySelector && el.querySelector(BLOCK_SELECTOR)) continue;
            let txt = el.textContent || "";
            txt = txt.replace(/\s+/g, " ").trim();
            if (!txt) continue;
            let bid = el.getAttribute("data-vreader-bid");
            if (!bid || !TRUSTED_BID.test(bid)) {
              seq += 1;
              bid = "fb" + seq;
              el.setAttribute("data-vreader-bid", bid);
            }
            out.push({
              bid,
              text: txt,
              sectionIndex
            });
          }
          doc.__vreaderBilingualSeq = seq;
        }
        post("bilingualEnumerate", {
          requestedSectionIndex: reqIdx,
          blocks: out
        });
      } catch (e3) {
        console.warn("[foliate-host] bilingualEnumerate failed:", e3);
        post("bilingualEnumerate", {
          requestedSectionIndex: reqIdx,
          blocks: []
        });
      }
    },
    // Feature #56 WI-11: inject a translation `<div>` after each
    // stamped block in a specific section's DOM. `opts` is the
    // payload `FoliateBilingualJS.bilingualInjectJS` emits:
    //
    //   { translations: {bid: text, ...},
    //     decorationAttribute, blockIDAttribute, blockClassName,
    //     styleCssText,
    //     targetSectionIndex: Int | null }
    //
    // Gate-4 audit finding H2: scope the inject walk to the
    // requested section. With multiple sections loaded
    // simultaneously (paginated mode), an unscoped walk would
    // let one unit's translations leak into adjacent sections.
    // `targetSectionIndex == null` falls back to "every loaded
    // section" (the original behaviour) so a future bulk-inject
    // path stays open.
    //
    // Gate-4 audit finding M2: bid keys come from the (trusted)
    // Swift Pipeline and were stamped by `bilingualEnumerate`'s
    // re-stamping logic (any third-party value not matching
    // `^fb\d+$` is overwritten before its bid enters the
    // pipeline). Even so, we use `CSS.escape` defensively so the
    // selector is always well-formed regardless of upstream
    // contract changes.
    //
    // Idempotent: if a decoration sibling already exists for a
    // block, its `textContent` is replaced in place rather than a
    // second sibling appended.
    bilingualInject(opts) {
      try {
        const translations = opts?.translations || {};
        const DECO = opts?.decorationAttribute || "data-vreader-decoration";
        const BID = opts?.blockIDAttribute || "data-vreader-bid";
        const CLS = opts?.blockClassName || "vreader-bilingual";
        const STYLE = opts?.styleCssText || "user-select: none; -webkit-user-select: none;";
        const targetSectionIndex = opts?.targetSectionIndex;
        const contents = view.renderer?.getContents?.();
        if (!Array.isArray(contents) || contents.length === 0) return;
        const esc = typeof CSS !== "undefined" && CSS.escape ? CSS.escape : (s3) => String(s3).replace(/[^a-zA-Z0-9_-]/g, "\\$&");
        for (const entry of contents) {
          const doc = entry?.doc;
          if (!doc) continue;
          const sectionIndex = typeof entry.index === "number" ? entry.index : -1;
          if (targetSectionIndex != null && sectionIndex !== targetSectionIndex) {
            continue;
          }
          for (const bid in translations) {
            if (!Object.prototype.hasOwnProperty.call(translations, bid)) {
              continue;
            }
            const block = doc.querySelector(
              "[" + BID + '="' + esc(bid) + '"]'
            );
            if (!block) continue;
            const next = block.nextElementSibling;
            if (next && next.hasAttribute && next.hasAttribute(DECO) && next.classList && next.classList.contains(CLS)) {
              next.classList.remove("vreader-bilingual-loading");
              next.textContent = translations[bid];
              continue;
            }
            const div = doc.createElement("div");
            div.className = CLS;
            div.setAttribute(DECO, "");
            div.style.cssText = STYLE;
            div.textContent = translations[bid];
            if (block.parentNode) {
              block.parentNode.insertBefore(div, block.nextSibling);
            }
          }
        }
      } catch (e3) {
        console.warn("[foliate-host] bilingualInject failed:", e3);
      }
    },
    // Feature #56 WI-11: remove every `vreader-bilingual` node from
    // loaded section DOMs. With `targetSectionIndex` omitted, walks
    // every section (the safe default on disable / book close).
    // Safe to run multiple times — an empty NodeList is a no-op.
    bilingualClear(targetSectionIndex) {
      try {
        const contents = view.renderer?.getContents?.();
        if (!Array.isArray(contents) || contents.length === 0) return;
        for (const entry of contents) {
          const doc = entry?.doc;
          if (!doc) continue;
          const sectionIndex = typeof entry.index === "number" ? entry.index : -1;
          if (targetSectionIndex != null && sectionIndex !== targetSectionIndex) {
            continue;
          }
          const nodes = doc.querySelectorAll(
            ".vreader-bilingual[data-vreader-decoration]"
          );
          for (let i3 = 0; i3 < nodes.length; i3++) {
            const n3 = nodes[i3];
            if (n3.parentNode) {
              n3.parentNode.removeChild(n3);
            }
          }
        }
      } catch (e3) {
        console.warn("[foliate-host] bilingualClear failed:", e3);
      }
    },
    // Feature #77: insert an inline LOADING shimmer decoration after each
    // of `opts.loadingBids`' blocks while that unit's translation is being
    // fetched. Skips any block that already carries a decoration (a landed
    // translation OR an existing shimmer) so it never downgrades a translated
    // row or stacks duplicates. The shimmer node is `<div class="vreader-
    // bilingual vreader-bilingual-loading" data-vreader-decoration>` with two
    // `<div class="vreader-shimmer-bar">` children; the inject path above
    // replaces it in place (dropping the loading class) when the translation
    // lands. Mirrors `EPUBBilingualJS.bilingualInjectLoadingJS`.
    bilingualInjectLoading(opts) {
      try {
        const loadingBids = Array.isArray(opts?.loadingBids) ? opts.loadingBids : [];
        if (loadingBids.length === 0) return;
        const DECO = opts?.decorationAttribute || "data-vreader-decoration";
        const BID = opts?.blockIDAttribute || "data-vreader-bid";
        const CLS = opts?.blockClassName || "vreader-bilingual";
        const LOADING_CLS = opts?.loadingClassName || "vreader-bilingual-loading";
        const BAR_CLS = opts?.shimmerBarClassName || "vreader-shimmer-bar";
        const STYLE = opts?.styleCssText || "user-select: none; -webkit-user-select: none;";
        const targetSectionIndex = opts?.targetSectionIndex;
        const WIDTHS = ["92%", "54%"];
        const contents = view.renderer?.getContents?.();
        if (!Array.isArray(contents) || contents.length === 0) return;
        const esc = typeof CSS !== "undefined" && CSS.escape ? CSS.escape : (s3) => String(s3).replace(/[^a-zA-Z0-9_-]/g, "\\$&");
        for (const entry of contents) {
          const doc = entry?.doc;
          if (!doc) continue;
          const sectionIndex = typeof entry.index === "number" ? entry.index : -1;
          if (targetSectionIndex != null && sectionIndex !== targetSectionIndex) {
            continue;
          }
          for (let b3 = 0; b3 < loadingBids.length; b3++) {
            const block = doc.querySelector(
              "[" + BID + '="' + esc(loadingBids[b3]) + '"]'
            );
            if (!block) continue;
            const next = block.nextElementSibling;
            if (next && next.hasAttribute && next.hasAttribute(DECO) && next.classList && next.classList.contains(CLS)) {
              continue;
            }
            const div = doc.createElement("div");
            div.className = CLS + " " + LOADING_CLS;
            div.setAttribute(DECO, "");
            div.style.cssText = STYLE;
            for (let w2 = 0; w2 < WIDTHS.length; w2++) {
              const bar = doc.createElement("div");
              bar.className = BAR_CLS;
              bar.style.width = WIDTHS[w2];
              div.appendChild(bar);
            }
            if (block.parentNode) {
              block.parentNode.insertBefore(div, block.nextSibling);
            }
          }
        }
      } catch (e3) {
        console.warn("[foliate-host] bilingualInjectLoading failed:", e3);
      }
    },
    // Feature #77: remove ONLY the loading-shimmer decoration nodes (a failed
    // / cancelled prefetch), leaving landed translations intact. With
    // `targetSectionIndex` omitted, walks every loaded section. Idempotent.
    bilingualClearLoading(targetSectionIndex) {
      try {
        const contents = view.renderer?.getContents?.();
        if (!Array.isArray(contents) || contents.length === 0) return;
        for (const entry of contents) {
          const doc = entry?.doc;
          if (!doc) continue;
          const sectionIndex = typeof entry.index === "number" ? entry.index : -1;
          if (targetSectionIndex != null && sectionIndex !== targetSectionIndex) {
            continue;
          }
          const nodes = doc.querySelectorAll(
            ".vreader-bilingual-loading[data-vreader-decoration]"
          );
          for (let i3 = 0; i3 < nodes.length; i3++) {
            const n3 = nodes[i3];
            if (n3.parentNode) {
              n3.parentNode.removeChild(n3);
            }
          }
        }
      } catch (e3) {
        console.warn("[foliate-host] bilingualClearLoading failed:", e3);
      }
    },
    // Cleanup
    close() {
      view.close();
      bookReady = false;
      currentBook = null;
    },
    // Debug
    getState() {
      return {
        bookReady,
        lastLocation: view.lastLocation,
        sections: currentBook?.sections?.length ?? 0
      };
    }
  };
  function serializeTOC(toc) {
    if (!toc) return [];
    return toc.map((item) => ({
      label: item.label ?? "",
      href: item.href ?? "",
      subitems: item.subitems ? serializeTOC(item.subitems) : []
    }));
  }
  post("bridge-ready", {});
})();
