/** @odoo-module **/

import { Component, useState, onMounted } from "@odoo/owl";
import { registry } from "@web/core/registry";
import { useService } from "@web/core/utils/hooks";
import { loadJS } from "@web/core/assets";

export class TraiteurDashboard extends Component {
    static template = "invoice_qr_scanner.TraiteurDashboard";
    static props = ["*"];

    setup() {
        this.orm = useService("orm");
        this.action = useService("action");
        
        this.state = useState({
            loading: true,
            period: "month",
            stats: {
                pending_count: 0,
                pending_amount: 0,
                processed_period: 0,
                processed_amount_period: 0,
                all_processed_period: 0,
                processing_rate: 0,
            },
            all_time_stats: {
                processed_all_time: 0,
                processed_all_amount: 0,
            },
            recent_processed: [],
            pending_scans: [],
            chart_data: { labels: [], processed: [] },
        });
        
        this.evolutionChart = null;

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
                "get_traiteur_dashboard_data",
                [this.state.period]
            );
            this.state.stats = result.stats || this.state.stats;
            this.state.all_time_stats = result.all_time_stats || this.state.all_time_stats;
            this.state.recent_processed = result.recent_processed || [];
            this.state.pending_scans = result.pending_scans || [];
            this.state.chart_data = result.chart_data || this.state.chart_data;
            this.renderChart();
        } catch (error) {
            console.error("Traiteur Dashboard error:", error);
        } finally {
            this.state.loading = false;
        }
    }

    renderChart() {
        if (typeof Chart === 'undefined') return;
        const canvas = document.getElementById('traiteurEvolutionChart');
        if (!canvas) return;
        if (this.evolutionChart) this.evolutionChart.destroy();
        
        const ctx = canvas.getContext('2d');
        this.evolutionChart = new Chart(ctx, {
            type: 'bar',
            data: {
                labels: this.state.chart_data.labels || [],
                datasets: [
                    {
                        label: 'Factures traitées',
                        data: this.state.chart_data.processed || [],
                        backgroundColor: 'rgba(0, 123, 255, 0.7)',
                        borderColor: '#007bff',
                        borderWidth: 1,
                        borderRadius: 4,
                    },
                ],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { position: 'bottom', labels: { padding: 15, usePointStyle: true } },
                },
                scales: {
                    y: { beginAtZero: true, ticks: { stepSize: 1 } },
                    x: { grid: { display: false } },
                },
            },
        });
    }

    onPeriodChange(ev) {
        this.state.period = ev.target.value;
        this.loadDashboardData();
    }

    formatNumber(value) {
        return (value || 0).toLocaleString('fr-FR');
    }

    formatCurrency(value) {
        return (value || 0).toLocaleString('fr-FR') + ' FCFA';
    }

    formatDate(isoDate) {
        if (!isoDate) return 'N/A';
        try {
            const d = new Date(isoDate);
            return d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
        } catch {
            return isoDate;
        }
    }

    viewPendingScans() {
        this.action.doAction({
            type: 'ir.actions.act_window',
            name: 'Factures en attente de traitement',
            res_model: 'invoice.scan.record',
            view_mode: 'tree,form',
            domain: [['state', '=', 'done'], ['processed_by', '=', false]],
        });
    }

    viewMyProcessed() {
        this.action.doAction({
            type: 'ir.actions.act_window',
            name: 'Mes factures traitées',
            res_model: 'invoice.scan.record',
            view_mode: 'tree,form',
            domain: [['state', '=', 'processed'], ['processed_by', '=', this.orm.env.uid]],
        });
    }

    viewAllProcessed() {
        this.action.doAction({
            type: 'ir.actions.act_window',
            name: 'Toutes les factures traitées',
            res_model: 'invoice.scan.record',
            view_mode: 'tree,form',
            domain: [['state', '=', 'processed']],
        });
    }
}

registry.category("actions").add("traiteur_dashboard", TraiteurDashboard);
