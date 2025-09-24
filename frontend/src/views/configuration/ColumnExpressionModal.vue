<template>
  <b-modal :active="show" @close="$emit('close')">
    <div class="modal-card">
      <header class="modal-card-head">
        <p class="modal-card-title">Column Expressions ({{ operation }})</p>
        <button class="delete" @click="$emit('close')"></button>
      </header>
      <section class="modal-card-body">
        <b-table :data="expressions" :striped="true" :hoverable="true">
          <b-table-column field="expression" label="Expression" v-slot="props">
            {{ props.row.sql }}
          </b-table-column>
        </b-table>
      </section>
      <footer class="modal-card-foot">
        <b-button type="is-primary" @click="$emit('close')">Close</b-button>
      </footer>
    </div>
  </b-modal>
</template>

<script>
export default {
  name: 'ColumnExpressionModal',
  props: {
    show: Boolean,
    expressions: Array,
    operation: String,
  },
};
</script>
