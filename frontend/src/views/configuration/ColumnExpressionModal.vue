<template>
  <b-modal :active="show" @close="$emit('close')">
    <div class="modal-card" style="width: 100%">
      <header class="modal-card-head">
        <p class="modal-card-title">SQL Expressions for operation '{{ operation }}'</p>
        <button class="delete" @click="$emit('close')"></button>
      </header>
      <section class="modal-card-body">
        <b-table :data="localExpressions" :striped="true" :hoverable="true">
          <b-table-column field="sql" label="SQL Expression" v-slot="props">
            {{ props.row.sql }}
          </b-table-column>
          <b-table-column label="" v-slot="props" class="is-pulled-right">
            <b-tooltip label="Edit">
              <b-button icon-right="pencil" size="is-small" @click="editExpression(props.row)"/>
            </b-tooltip>
          </b-table-column>
        </b-table>
      </section>
      <footer class="modal-card-foot">
        <b-button type="is-primary" @click="$emit('close')">Close</b-button>
        <b-button type="is-success" @click="openNewExpressionModal">New Expression</b-button>
      </footer>
    </div>
    <edit-column-expression-modal
      :show="editModal.show"
      :expression="editModal.expression"
      @close="closeEditModal"
      @save="saveExpression"
      @remove="removeExpression"
    />
  </b-modal>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import EditColumnExpressionModal from './EditColumnExpressionModal.vue';

export default {
  name: 'ColumnExpressionModal',
  components: { EditColumnExpressionModal },
  props: {
    show: Boolean,
    expressions: Array,
    operation: String,
    tableId: [String, Number],
  },
  data() {
    return {
      localExpressions: [],
      editModal: {
        show: false,
        expression: {},
      },
    };
  },
  watch: {
    expressions: {
      immediate: true,
      handler(newVal) {
        this.localExpressions = [...newVal];
      },
    },
    operation: {
      immediate: true,
      handler() {
        this.reloadExpressions();
      },
    },
    show(val) {
      if (val) this.reloadExpressions();
    },
  },
  mounted() {
    this.$on('expression-saved', this.reloadExpressions);
  },
  methods: {
    async reloadExpressions() {
      if (!this.tableId || !this.operation) return;
      try {
        const allExpr = await CRUDService.columnExpressions.getAll({ table_id: this.tableId });
        this.localExpressions = allExpr.filter((e) => e.operation === this.operation);
      } catch (e) {
        console.log(`error in reloadExpressions ${e}`);
      }
    },
    openNewExpressionModal() {
      this.editModal.expression = { sql: '', operation: this.operation };
      this.editModal.show = true;
    },
    editExpression(expr) {
      this.editModal.expression = { ...expr };
      this.editModal.show = true;
    },
    closeEditModal() {
      this.editModal.show = false;
    },
    async saveExpression(expr) {
      const newExpr = { ...expr };
      if (!newExpr.table_id) {
        newExpr.table_id = this.tableId;
      }
      this.$emit('save-expression', newExpr);
      this.editModal.show = false;
    },
    async removeExpression(expr) {
      const newExpr = { ...expr };
      this.$emit('remove-expression', newExpr);
      this.editModal.show = false;
    },
  },
};
</script>
