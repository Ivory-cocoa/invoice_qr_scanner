/** @odoo-module **/

import { Component, useState, onMounted } from "@odoo/owl";
import { registry } from "@web/core/registry";
import { useService } from "@web/core/utils/hooks";
import { loadJS } from "@web/core/assets";

export class VerificateurDashboard extends Component {
    static template = "invoice_qr_scanner.VerificateurDashboard";
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
                duplicate_attempts: 0,
                duplicates_by_others: 0,
                error_scans: 0,
                total_amount: 0,
            },
            all_time_stats: {
                total_scans: 0,
                successful_scans: 0,
                duplicate_attempts: 0,
                error_scans: 0,
                total_amount: 0,
            },
            recent_scans: [],
            top_suppliers: [],
            chart_data: { labels: [], scans: [], duplicates: [] },
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
                "get_verificateur_dashboard_data",
                [this.state.period]
            );
            this.state.stats = result.stats || this.state.stats;
            this.state.all_time_stats = result.all_time_stats || this.state.all_time_stats;
            this.state.recent_scans = result.recent_scans || [];
            this.state.top_suppliers = result.top_suppliers || [];
            this.state.chart_data = result.chart_data || this.state.chart_data;
            this.renderChart();
        } catch (error) {
            console.error("Verificateur Dashboard error:", error);
        } finally {
            this.state.loading = false;
        }
    }

    renderChart() {
        if (typeof Chart === 'undefined') return;
        const canvas = document.getElementById('verificateurEvolutionChart');
        if (!canvas) return;
        if (this.evolutionChart) this.evolutionChart.destroy();
        
        const ctx = canvas.getContext('2d');
        this.evolutionChart = new Chart(ctx, {
            type: 'bar',
            data: {
                labels: this.state.chart_data.labels || [],
                datasets: [
                    {
                        label: 'Factures créées',
                        data: this.state.chart_data.scans || [],
                        backgroundColor: 'rgba(40, 167, 69, 0.7)',
                        borderColor: '#28a745',
                        borderWidth: 1,
                        borderRadius: 4,
                    },
                    {
                        label: 'Doublons détectés',
                        data: this.state.chart_data.duplicates || [],
                        backgroundColor: 'rgba(255, 193, 7, 0.7)',
                        borderColor: '#ffc107',
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

    getStateClass(state) {
        const classes = {
            'done': 'badge bg-success',
            'processed': 'badge bg-info',
            'error': 'badge bg-danger',
            'draft': 'badge bg-secondary',
        };
        return classes[state] || 'badge bg-secondary';
    }

    getStateLabel(state) {
        const labels = {
            'done': 'Facture créée',
            'processed': 'Traité',
            'error': 'Erreur',
            'draft': 'Brouillon',
        };
        return labels[state] || state;
    }

    viewMyScans() {
        this.action.doAction({
            type: 'ir.actions.act_window',
            name: 'Mes scans',
            res_model: 'invoice.scan.record',
            view_mode: 'tree,form',
            domain: [['scanned_by', '=', this.orm.env.uid]],
        });
    }

    viewMySuccessfulScans() {
        this.action.doAction({
            type: 'ir.actions.act_window',
            name: 'Mes factures créées',
            res_model: 'invoice.scan.record',
            view_mode: 'tree,form',
            domain: [['scanned_by', '=', this.orm.env.uid], ['state', 'in', ['done', 'processed']]],
        });
    }

    viewMyDuplicates() {
        this.action.doAction({
            type: 'ir.actions.act_window',
            name: 'Mes doublons détectés',
            res_model: 'invoice.scan.record',
            view_mode: 'tree,form',
            domain: [['scanned_by', '=', this.orm.env.uid], ['duplicate_count', '>', 0]],
        });
    }

    viewMyErrors() {
        this.action.doAction({
            type: 'ir.actions.act_window',
            name: 'Mes erreurs',
            res_model: 'invoice.scan.record',
            view_mode: 'tree,form',
            domain: [['scanned_by', '=', this.orm.env.uid], ['state', '=', 'error']],
        });
    }
}

registry.category("actions").add("verificateur_dashboard", VerificateurDashboard);
