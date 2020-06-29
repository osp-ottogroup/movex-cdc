<template>
  <b-modal id="table-modal"
           :active="true"
           has-modal-card
           trap-focus
           aria-role="dialog"
           aria-modal
           @close="onClose">
    <div class="modal-card" style="width: auto">
      <header class="modal-card-head">
        <p class="modal-card-title">{{title}}</p>
        <button class="delete"
                aria-label="close"
                @click="onClose">
        </button>
      </header>

      <section class="modal-card-body">
        <b-field v-if="showTableSelect" label="Table">
          <b-select ref="tableSelect"
                    v-model="internalTable.name"
                    placeholder="Select a table"
                    required
                    validation-message="Select a table to add"
                    expanded>
            <option v-for="(table, index) in tables" :key="index" :value="table.name">
              {{ table.name }}
            </option>
          </b-select>
        </b-field>

        <b-field label="Kafka-Topic">
          <b-input ref="topicInput"
                   placeholder="Enter Kafka-Topic"
                   :required="!schema.topic && !internalTable.topic"
                   validation-message="Add a topic to the table because the schema has none"
                   v-model="internalTable.topic"/>
        </b-field>

        <b-field label="Kafka Key Handling">
          <b-field>
            <b-select v-model="internalTable.kafka_key_handling" expanded>
              <option v-for="option in kafkaKeyHandlingOptions" :key="option.value" :value="option.value">
                {{ option.label }}
              </option>
            </b-select>
            <b-field v-if="internalTable.kafka_key_handling === 'F'">
              <b-input ref="fixedMessageInput"
                       v-model="internalTable.fixed_message_key"
                       placeholder="Fixed Message Key"
                       required/>
            </b-field>
          </b-field>
        </b-field>

        <b-field label="Info">
          <b-input ref="infoTextarea"
                   type="textarea"
                   rows="1"
                   v-model="internalTable.info"
                   required
                   validation-message="Add an info text why this table is used in TriXX"/>
        </b-field>

        <template v-if="!isAddMode">
          <b-field label="Date Of Last Trigger Deployment" custom-class="is-small" class="trigger-dates">
            <div class="columns is-1 is-variable">
              <div class="column">
                <b-field label="Insert" custom-class="is-small has-text-grey">
                  <b-input size="is-small" disabled :value="triggerDates.youngest_insert_trigger_changed_at"/>
                </b-field>
              </div>
              <div class="column">
                <b-field label="Update" custom-class="is-small has-text-grey">
                  <b-input size="is-small" disabled :value="triggerDates.youngest_update_trigger_changed_at"/>
                </b-field>
              </div>
              <div class="column">
                <b-field label="Delete" custom-class="is-small has-text-grey">
                  <b-input size="is-small" disabled :value="triggerDates.youngest_delete_trigger_changed_at"/>
                </b-field>
              </div>
            </div>
          </b-field>
        </template>
      </section>

      <footer class="modal-card-foot">
        <button id="save-table-button"
                class="button is-primary"
                @click="onSave">
          Save
        </button>
      </footer>
    </div>
  </b-modal>
</template>

<script>
import CRUDService from '@/services/CRUDService';

export default {
  name: 'TableModal',
  props: {
    tables: { type: Array, default: () => [] },
    table: { type: Object, default: () => {} },
    schema: { type: Object, default: () => {} },
    isActive: { type: Boolean, default: false },
    mode: { type: String, default: 'ADD' }, // 'ADD' or 'EDIT'
  },
  data() {
    return {
      internalTable: { ...this.table },
      triggerDates: {},
      kafkaKeyHandlingOptions: [
        { value: 'N', label: 'N - None' },
        { value: 'P', label: 'P - Primary Key' },
        { value: 'F', label: 'F - Fixed Key' },
      ],
    };
  },
  async created() {
    if (!this.isAddMode) {
      this.triggerDates = await CRUDService.tables.triggerDates(this.table.id);
      if (!this.triggerDates.youngest_insert_trigger_changed_at) {
        this.triggerDates.youngest_insert_trigger_changed_at = 'never';
      }
      if (!this.triggerDates.youngest_update_trigger_changed_at) {
        this.triggerDates.youngest_update_trigger_changed_at = 'never';
      }
      if (!this.triggerDates.youngest_delete_trigger_changed_at) {
        this.triggerDates.youngest_delete_trigger_changed_at = 'never';
      }
    }
  },
  computed: {
    title() {
      if (this.mode === 'ADD') {
        return 'Add table to observe';
      }
      return `Edit observed table (${this.internalTable.name})`;
    },
    showTableSelect() {
      return this.isAddMode;
    },
    isAddMode() {
      return this.mode === 'ADD';
    },
  },
  methods: {
    onClose() {
      this.$emit('close');
    },
    onSave() {
      if (this.showTableSelect) {
        this.$refs.tableSelect.checkHtml5Validity();
      }
      this.$refs.topicInput.checkHtml5Validity();
      this.$refs.infoTextarea.checkHtml5Validity();
      if (this.internalTable.kafka_key_handling === 'F') {
        this.$refs.fixedMessageInput.checkHtml5Validity();
      } else {
        this.internalTable.fixed_message_key = null;
      }
      const invalidFields = document.querySelectorAll('#table-modal :invalid');
      if (invalidFields.length > 0) {
        // invalidFields.forEach(field => field.dispatchEvent(new Event('blur')));
        return;
      }
      this.$emit('save', this.internalTable);
    },
  },
};
</script>

<style lang="scss" scoped>
  footer button {
    margin-left: auto;
  }
  .trigger-dates {
    margin-top: 2rem;
  }
</style>
