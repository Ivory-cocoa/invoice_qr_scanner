/** @odoo-module **/

import { Component, useState, onMounted } from "@odoo/owl";
import { registry } from "@web/core/registry";
import { useService } from "@web/core/utils/hooks";
import { loadJS } from "@web/core/assets";

export class InvoiceScannerDashboardImproved extends Component {
    static template = "invoice_qr_scanner.DashboardImproved";
    static props = ["*"];

    setup() {
        this.orm = useService("orm");
        this.action = useService("action");
        
        this.state = useState({
            loading: true,
            period: "month",
            stats: {
                total_scans: 0,
                successful_scans: 0,
                processed_scans: 0,
                duplicate_attempts: 0,
                records_with_duplicates: 0,
                error_scans: 0,
                total_amount: 0,
            },
            // Stats globales (all-time) pour correspondre à l'application mobile
            all_time_stats: {
                total_scans: 0,
                successful_scans: 0,
                processed_scans: 0,
                duplicate_attempts: 0,
                records_with_duplicates: 0,
                error_scans: 0,
                total_amount: 0,
            },
            recent_scans: [],
            top_suppliers: [],
            chart_data: { labels: [], scans: [], verified: [] },
        });
        
        this.evolutionChart = null;
        this.statusChart = null;

        onMounted(async () => {
            await loadJS("https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js");
            await this.loadDashboardData();
        });
    }

    async loadDashboardData() {
        this.state.loading = true;
        
        try {
            const result = await this.orm.call(
                "invoice.scan.record",
                "get_dashboard_stats",
                [null, null, this.state.period]
            );
            
            this.state.stats = result.stats || this.state.stats;
            this.state.all_time_stats = result.all_time_stats || this.state.all_time_stats;
            this.state.recent_scans = result.recent_scans || [];
            this.state.top_suppliers = result.top_suppliers || [];
            this.state.chart_data = result.chart_data || this.state.chart_data;
            
            this.renderCharts();
        } catch (error) {
            console.error("Dashboard error:", error);
            // Afficher un état vide plutôt que des données démo
            const emptyStats = {
                total_scans: 0,
                successful_scans: 0,
                processed_scans: 0,
                duplicate_attempts: 0,
                records_with_duplicates: 0,
                error_scans: 0,
                total_amount: 0,
            };
            this.state.stats = emptyStats;
            this.state.all_time_stats = emptyStats;
            this.state.recent_scans = [];
            this.state.top_suppliers = [];
            this.state.chart_data = { labels: [], scans: [], verified: [] };
        } finally {
            this.state.loading = false;
        }
    }

    getDateRange() {
        const now = new Date();
        let start = new Date();
        
        switch (this.state.period) {
            case "day": start.setHours(0, 0, 0, 0); break;
            case "week": start.setDate(now.getDate() - 7); break;
            case "month": start.setMonth(now.getMonth() - 1); break;
            case "year": start.setFullYear(now.getFullYear() - 1); break;
        }
        
        return {
            start: start.toISOString().split("T")[0],
            end: now.toISOString().split("T")[0],
        };
    }

    onPeriodChange(ev) {
        this.state.period = ev.target.value;
        this.loadDashboardData();
    }

    renderCharts() {
        this.renderEvolutionChart();
        this.renderStatusChart();
    }

    renderEvolutionChart() {
        const ctx = document.getElementById("evolutionChart");
        if (!ctx || typeof Chart === "undefined") return;
        
        if (this.evolutionChart) this.evolutionChart.destroy();
        
        this.evolutionChart = new Chart(ctx, {
            type: "line",
            data: {
                labels: this.state.chart_data.labels,
                datasets: [{
                    label: "Scans",
                    data: this.state.chart_data.scans,
                    borderColor: "#714B67",
                    backgroundColor: "rgba(113, 75, 103, 0.1)",
                    borderWidth: 2,
                    fill: true,
                    tension: 0.4,
                    pointRadius: 0,
                    pointHoverRadius: 4,
                }],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        backgroundColor: "#1e293b",
                        padding: 10,
                        cornerRadius: 6,
                        titleFont: { size: 12 },
                        bodyFont: { size: 11 },
                    },
                },
                scales: {
                    x: {
                        grid: { display: false },
                        ticks: { color: "#94a3b8", font: { size: 11 } },
                    },
                    y: {
                        beginAtZero: true,
                        grid: { color: "#f1f5f9" },
                        ticks: { color: "#94a3b8", font: { size: 11 } },
                    },
                },
                interaction: { intersect: false, mode: "index" },
            },
        });
    }

    renderStatusChart() {
        const ctx = document.getElementById("statusChart");
        if (!ctx || typeof Chart === "undefined") return;
        
        if (this.statusChart) this.statusChart.destroy();
        
        const { successful_scans, processed_scans, duplicate_attempts, error_scans } = this.state.stats;
        const unprocessed = Math.max(0, successful_scans - (processed_scans || 0));
        
        this.statusChart = new Chart(ctx, {
            type: "doughnut",
            data: {
                labels: ["Traités", "Non traités", "Tentatives doublons", "Erreurs"],
                datasets: [{
                    data: [processed_scans || 0, unprocessed, duplicate_attempts, error_scans],
                    backgroundColor: ["#5C6BC0", "#2E7D32", "#EF6C00", "#C62828"],
                    borderWidth: 0,
                }],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                cutout: "65%",
                plugins: {
                    legend: {
                        position: "bottom",
                        labels: {
                            padding: 16,
                            usePointStyle: true,
                            pointStyle: "circle",
                            font: { size: 11 },
                            color: "#64748b",
                        },
                    },
                    tooltip: {
                        backgroundColor: "#1e293b",
                        padding: 10,
                        cornerRadius: 6,
                    },
                },
            },
        });
    }

    formatNumber(value) {
        if (!value && value !== 0) return "0";
        return new Intl.NumberFormat("fr-FR").format(value);
    }

    formatCurrency(value) {
        if (!value && value !== 0) return "0 FCFA";
        return new Intl.NumberFormat("fr-FR").format(value) + " FCFA";
    }

    truncate(text, length) {
        if (!text) return "-";
        return text.length > length ? text.substring(0, length) + "..." : text;
    }

    openRecord(id) {
        this.action.doAction({
            type: "ir.actions.act_window",
            res_model: "invoice.scan.record",
            res_id: id,
            views: [[false, "form"]],
            target: "current",
        });
    }

    viewAllRecords() {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Scans",
            res_model: "invoice.scan.record",
            views: [[false, "list"], [false, "form"]],
            target: "current",
        });
    }

    createNewScan() {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Nouveau Scan",
            res_model: "invoice.scan.record",
            views: [[false, "form"]],
            target: "current",
        });
    }

    viewReports() {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Rapports",
            res_model: "invoice.scan.record",
            views: [[false, "pivot"], [false, "graph"]],
            target: "current",
        });
    }

    // === Méthodes de navigation pour les KPIs ===

    viewTotalScans() {
        const context = this._getPeriodContext();
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Total des scans",
            res_model: "invoice.scan.record",
            views: [[false, "list"], [false, "kanban"], [false, "form"]],
            target: "current",
            domain: this._getPeriodDomain(),
            context: context,
        });
    }

    viewSuccessfulScans() {
        const context = this._getPeriodContext();
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Scans réussis",
            res_model: "invoice.scan.record",
            views: [[false, "list"], [false, "kanban"], [false, "form"]],
            target: "current",
            domain: [...this._getPeriodDomain(), ["state", "in", ["done", "processed"]]],
            context: context,
        });
    }

    viewProcessedScans() {
        const context = this._getPeriodContext();
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Scans traités",
            res_model: "invoice.scan.record",
            views: [[false, "list"], [false, "kanban"], [false, "form"]],
            target: "current",
            domain: [...this._getPeriodDomain(), ["state", "=", "processed"]],
            context: context,
        });
    }

    viewUnprocessedScans() {
        const context = this._getPeriodContext();
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Scans non traités",
            res_model: "invoice.scan.record",
            views: [[false, "list"], [false, "kanban"], [false, "form"]],
            target: "current",
            domain: [...this._getPeriodDomain(), ["state", "=", "done"]],
            context: context,
        });
    }

    viewDuplicateScans() {
        const context = this._getPeriodContext();
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Scans avec doublons",
            res_model: "invoice.scan.record",
            views: [[false, "list"], [false, "kanban"], [false, "form"]],
            target: "current",
            domain: [...this._getPeriodDomain(), ["duplicate_count", ">", 0]],
            context: context,
        });
    }

    viewErrorScans() {
        const context = this._getPeriodContext();
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Scans en erreur",
            res_model: "invoice.scan.record",
            views: [[false, "list"], [false, "form"]],
            target: "current",
            domain: [...this._getPeriodDomain(), ["state", "=", "error"]],
            context: context,
        });
    }

    // KPIs globaux (all-time)
    viewAllTimeTotalScans() {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Total des scans (global)",
            res_model: "invoice.scan.record",
            views: [[false, "list"], [false, "kanban"], [false, "form"]],
            target: "current",
        });
    }

    viewAllTimeSuccessfulScans() {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Scans réussis (global)",
            res_model: "invoice.scan.record",
            views: [[false, "list"], [false, "kanban"], [false, "form"]],
            target: "current",
            domain: [["state", "in", ["done", "processed"]]],
        });
    }

    viewAllTimeProcessedScans() {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Scans traités (global)",
            res_model: "invoice.scan.record",
            views: [[false, "list"], [false, "kanban"], [false, "form"]],
            target: "current",
            domain: [["state", "=", "processed"]],
        });
    }

    viewAllTimeUnprocessedScans() {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Scans non traités (global)",
            res_model: "invoice.scan.record",
            views: [[false, "list"], [false, "kanban"], [false, "form"]],
            target: "current",
            domain: [["state", "=", "done"]],
        });
    }

    viewAllTimeDuplicateScans() {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Scans avec doublons (global)",
            res_model: "invoice.scan.record",
            views: [[false, "list"], [false, "kanban"], [false, "form"]],
            target: "current",
            domain: [["duplicate_count", ">", 0]],
        });
    }

    viewAllTimeErrorScans() {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Scans en erreur (global)",
            res_model: "invoice.scan.record",
            views: [[false, "list"], [false, "form"]],
            target: "current",
            domain: [["state", "=", "error"]],
        });
    }

    viewAllTimeAmount() {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Montant TTC (global)",
            res_model: "invoice.scan.record",
            views: [[false, "list"], [false, "kanban"], [false, "form"]],
            target: "current",
            domain: [["state", "in", ["done", "processed"]]],
        });
    }

    // Méthodes utilitaires pour le filtrage par période
    _getPeriodDomain() {
        const range = this.getDateRange();
        return [["scan_date", ">=", range.start], ["scan_date", "<=", range.end]];
    }

    _getPeriodContext() {
        return {};
    }
}

registry.category("actions").add("invoice_scanner_dashboard_improved", InvoiceScannerDashboardImproved);
