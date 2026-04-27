import { Router } from "express";
import { authMiddleware } from "../authMiddleware.js";
import { Sale } from "../models/Sale.js";
import { Shift } from "../models/Shift.js";
import { tenantFilter, withTenant } from "../tenant.js";

const router = Router();

function roundMoney(value) {
  return Math.round(Number(value) * 100) / 100;
}

function buildDateRangeQuery({ period, from, to }) {
  const parseLocalDateOnly = (value) => {
    if (!value) return null;
    const raw = String(value).trim();
    const match = raw.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (match) {
      const year = Number(match[1]);
      const month = Number(match[2]);
      const day = Number(match[3]);
      const parsed = new Date(year, month - 1, day, 0, 0, 0, 0);
      return Number.isNaN(parsed.getTime()) ? null : parsed;
    }

    const parsed = new Date(raw);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  };

  const query = {};
  const now = new Date();

  if (period === "today") {
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const end = new Date(start);
    end.setDate(end.getDate() + 1);
    query.$gte = start;
    query.$lt = end;
  } else if (period === "yesterday") {
    const end = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const start = new Date(end);
    start.setDate(start.getDate() - 1);
    query.$gte = start;
    query.$lt = end;
  } else if (period === "7d") {
    const start = new Date();
    start.setDate(start.getDate() - 7);
    query.$gte = start;
  } else if (period === "30d") {
    const start = new Date();
    start.setDate(start.getDate() - 30);
    query.$gte = start;
  } else if (from || to) {
    if (from) {
      const start = parseLocalDateOnly(from);
      if (start) query.$gte = start;
    }
    if (to) {
      const end = parseLocalDateOnly(to);
      if (end) {
        end.setHours(23, 59, 59, 999);
        query.$lte = end;
      }
    }
  }

  if (!query.$gte && !query.$lte && !query.$lt) return null;
  return query;
}

function buildShiftRangeQuery({ period, from, to }) {
  const range = buildDateRangeQuery({ period, from, to });
  if (!range) return null;

  const start = range.$gte || null;
  const end = range.$lt || range.$lte || null;

  if (start && end) {
    return {
      openedAt: { $lte: end },
      $or: [
        { closedAt: { $gte: start } },
        { closedAt: null },
        { closedAt: { $exists: false } }
      ]
    };
  }

  if (start) {
    return {
      $or: [
        { closedAt: { $gte: start } },
        { closedAt: null },
        { closedAt: { $exists: false } }
      ]
    };
  }

  if (end) {
    return {
      openedAt: { $lte: end }
    };
  }

  return null;
}

function buildShiftSalesQuery(req, shiftId, shiftDoc = null) {
  const query = tenantFilter(req, {
    entryType: { $ne: "opening_balance" },
    transactionType: { $ne: "debt_payment" }
  });

  if (!shiftDoc) {
    query.shiftId = shiftId;
    return query;
  }

  const shiftStart = shiftDoc.openedAt ? new Date(shiftDoc.openedAt) : null;
  const shiftEnd = shiftDoc.closedAt ? new Date(shiftDoc.closedAt) : new Date();
  const legacyClause = {
    $or: [{ shiftId: { $exists: false } }, { shiftId: null }],
    cashierUsername: shiftDoc.cashierUsername
  };
  if (shiftStart || shiftEnd) {
    legacyClause.createdAt = {};
    if (shiftStart) legacyClause.createdAt.$gte = shiftStart;
    if (shiftEnd) legacyClause.createdAt.$lte = shiftEnd;
  }

  query.$or = [{ shiftId }, legacyClause];
  return query;
}

async function summarizeShift(req, shiftId, shiftDoc = null) {
  const sales = await Sale.find(buildShiftSalesQuery(req, shiftId, shiftDoc)).lean();
  const shift = shiftDoc || await Shift.findOne(tenantFilter(req, { _id: shiftId }))
    .select("_id cashierUsername openedAt closedAt")
    .lean();

  let returnSummary = {
    totalAmount: 0,
    totalCash: 0,
    totalCard: 0,
    totalClick: 0
  };

  if (shift) {
    const shiftStart = shift.openedAt ? new Date(shift.openedAt) : null;
    const shiftEnd = shift.closedAt ? new Date(shift.closedAt) : new Date();
    const matchReturn = tenantFilter(req, { returns: { $exists: true, $ne: [] } });

    const rows = await Sale.aggregate([
      { $match: matchReturn },
      { $unwind: "$returns" },
      {
        $match: {
          $or: [
            { "returns.shiftId": shift._id },
            {
              "returns.shiftId": { $in: [null, undefined] },
              "returns.cashierUsername": shift.cashierUsername,
              ...(shiftStart || shiftEnd
                ? {
                    "returns.createdAt": {
                      ...(shiftStart ? { $gte: shiftStart } : {}),
                      ...(shiftEnd ? { $lte: shiftEnd } : {})
                    }
                  }
                : {})
            }
          ]
        }
      },
      {
        $group: {
          _id: null,
          totalAmount: { $sum: { $ifNull: ["$returns.totalAmount", 0] } },
          totalCash: { $sum: { $ifNull: ["$returns.payments.cash", 0] } },
          totalCard: { $sum: { $ifNull: ["$returns.payments.card", 0] } },
          totalClick: { $sum: { $ifNull: ["$returns.payments.click", 0] } }
        }
      }
    ]);
    const agg = rows[0] || {};
    returnSummary = {
      totalAmount: roundMoney(Number(agg.totalAmount || 0)),
      totalCash: roundMoney(Number(agg.totalCash || 0)),
      totalCard: roundMoney(Number(agg.totalCard || 0)),
      totalClick: roundMoney(Number(agg.totalClick || 0))
    };
  }

  const gross = sales.reduce(
    (acc, sale) => {
      const itemCount = (sale.items || []).reduce(
        (sum, item) => sum + Number(item.quantity || 0),
        0
      );
      return {
        totalSalesCount: acc.totalSalesCount + 1,
        totalItemsCount: roundMoney(acc.totalItemsCount + itemCount),
        totalAmount: roundMoney(
          acc.totalAmount + Number(sale.totalAmount || 0) + Number(sale.returnedAmount || 0)
        ),
        totalCash: roundMoney(acc.totalCash + Number(sale.payments?.cash || 0)),
        totalCard: roundMoney(acc.totalCard + Number(sale.payments?.card || 0)),
        totalClick: roundMoney(acc.totalClick + Number(sale.payments?.click || 0)),
        totalDebt: roundMoney(acc.totalDebt + Number(sale.debtAmount || 0)),
        lastSaleAt: !acc.lastSaleAt || new Date(sale.createdAt).getTime() > new Date(acc.lastSaleAt).getTime()
          ? sale.createdAt
          : acc.lastSaleAt
      };
    },
    {
      totalSalesCount: 0,
      totalItemsCount: 0,
      totalAmount: 0,
      totalCash: 0,
      totalCard: 0,
      totalClick: 0,
      totalDebt: 0,
      lastSaleAt: null
    }
  );

  return {
    ...gross,
    totalAmount: roundMoney(Math.max(0, gross.totalAmount - returnSummary.totalAmount)),
    totalCash: roundMoney(Math.max(0, gross.totalCash - returnSummary.totalCash)),
    totalCard: roundMoney(Math.max(0, gross.totalCard - returnSummary.totalCard)),
    totalClick: roundMoney(Math.max(0, gross.totalClick - returnSummary.totalClick))
  };
}

router.get("/current", authMiddleware, async (req, res) => {
  const shift = await Shift.findOne(
    tenantFilter(req, { cashierId: req.user.id, status: "open" })
  )
    .sort({ openedAt: -1 })
    .lean();

  return res.json({ shift: shift || null });
});

router.post("/open", authMiddleware, async (req, res) => {
  const existing = await Shift.findOne(
    tenantFilter(req, { cashierId: req.user.id, status: "open" })
  ).sort({ openedAt: -1 });
  if (existing) {
    return res.json({ shift: existing });
  }

  const shiftNumber =
    (await Shift.countDocuments(tenantFilter(req))) + 1;

  const shift = await Shift.create(
    withTenant(req, {
      cashierId: req.user.id,
      cashierUsername: req.user.username,
      shiftNumber,
      status: "open",
      openedAt: new Date()
    })
  );

  return res.status(201).json({ shift });
});

router.post("/current/close", authMiddleware, async (req, res) => {
  const shift = await Shift.findOne(
    tenantFilter(req, { cashierId: req.user.id, status: "open" })
  ).sort({ openedAt: -1 });
  if (!shift) {
    return res.status(404).json({ message: "Ochiq smena topilmadi" });
  }

  const summary = await summarizeShift(req, shift._id, shift);
  shift.status = "closed";
  shift.closedAt = new Date();
  shift.totalSalesCount = summary.totalSalesCount;
  shift.totalItemsCount = summary.totalItemsCount;
  shift.totalAmount = summary.totalAmount;
  shift.totalCash = summary.totalCash;
  shift.totalCard = summary.totalCard;
  shift.totalClick = summary.totalClick;
  shift.totalDebt = summary.totalDebt;
  shift.lastSaleAt = summary.lastSaleAt;
  await shift.save();

  return res.json({ shift });
});

router.get("/", authMiddleware, async (req, res) => {
  const period = String(req.query?.period || "").toLowerCase();
  const from = String(req.query?.from || "");
  const to = String(req.query?.to || "");
  const cashierUsername = String(req.query?.cashierUsername || "").trim();
  const status = String(req.query?.status || "").trim().toLowerCase();
  const limitRaw = Number(req.query?.limit);
  const limit = Number.isFinite(limitRaw) && limitRaw > 0
    ? Math.min(Math.floor(limitRaw), 5000)
    : 1000;

  const query = tenantFilter(req);
  const shiftRangeQuery = buildShiftRangeQuery({ period, from, to });
  if (shiftRangeQuery) {
    Object.assign(query, shiftRangeQuery);
  }
  if (cashierUsername) {
    query.cashierUsername = cashierUsername;
  }
  if (["open", "closed"].includes(status)) {
    query.status = status;
  }

  const shifts = await Shift.find(query)
    .sort({ openedAt: -1 })
    .limit(limit)
    .lean();

  const shiftSummaries = await Promise.all(
    shifts.map((shift) => summarizeShift(req, shift._id, shift))
  );
  const shiftsWithSummary = shifts.map((shift, index) => {
    const summary = shiftSummaries[index];
    return {
      ...shift,
      totalSalesCount: summary.totalSalesCount,
      totalItemsCount: summary.totalItemsCount,
      totalAmount: summary.totalAmount,
      totalCash: summary.totalCash,
      totalCard: summary.totalCard,
      totalClick: summary.totalClick,
      totalDebt: summary.totalDebt,
      lastSaleAt: summary.lastSaleAt || shift.lastSaleAt || null
    };
  });

  const summary = shiftsWithSummary.reduce(
    (acc, shift) => {
      acc.totalShifts += 1;
      if (shift.status === "open") acc.openShifts += 1;
      if (shift.status === "closed") acc.closedShifts += 1;
      acc.totalSalesCount += Number(shift.totalSalesCount || 0);
      acc.totalAmount = roundMoney(acc.totalAmount + Number(shift.totalAmount || 0));
      acc.totalCash = roundMoney(acc.totalCash + Number(shift.totalCash || 0));
      acc.totalCard = roundMoney(acc.totalCard + Number(shift.totalCard || 0));
      acc.totalClick = roundMoney(acc.totalClick + Number(shift.totalClick || 0));
      acc.totalDebt = roundMoney(acc.totalDebt + Number(shift.totalDebt || 0));
      return acc;
    },
    {
      totalShifts: 0,
      openShifts: 0,
      closedShifts: 0,
      totalSalesCount: 0,
      totalAmount: 0,
      totalCash: 0,
      totalCard: 0,
      totalClick: 0,
      totalDebt: 0
    }
  );

  return res.json({ shifts: shiftsWithSummary, summary });
});

export default router;
